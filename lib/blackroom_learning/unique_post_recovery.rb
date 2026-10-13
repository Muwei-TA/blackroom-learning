# frozen_string_literal: true
require 'digest'
require 'json'
require 'securerandom'

module BlackroomLearning
  # Core writes its duplicate cache before our outer SQL transaction commits.
  # Keep that protection, but attach evidence so an identical retry can recover
  # a key left by a proven abort (including process death, where ensure cannot run).
  module UniquePostRecovery
    CONTEXT_KEY = :blackroom_learning_unique_post_context
    WRITE = <<~LUA.freeze
      redis.call('SETEX', KEYS[1], ARGV[1], ARGV[2])
      redis.call('SETEX', KEYS[2], ARGV[1], ARGV[3])
      return 1
    LUA
    REMOVE = <<~LUA.freeze
      if redis.call('GET', KEYS[1]) == ARGV[1] and redis.call('GET', KEYS[2]) == ARGV[2] then
        return redis.call('DEL', KEYS[1], KEYS[2])
      end
      return 0
    LUA

    module_function

    def marker_key(user_id, request_key)
      "blackroom-learning:unique-post:#{user_id}:#{request_key}"
    end

    def with_submission(user, receipt, args)
      context = {
        user_id: user.id, request_key: receipt.request_key, kind: receipt.kind,
        request_digest: receipt.request_digest, input_hash: Digest::SHA256.hexdigest(args.fetch(:raw)),
        args: args.dup,
      }
      previous = Thread.current[CONTEXT_KEY]
      recover(context)
      Thread.current[CONTEXT_KEY] = context
      yield
    ensure
      Thread.current[CONTEXT_KEY] = previous
    end

    def recover(context)
      key = marker_key(context[:user_id], context[:request_key])
      bytes = Discourse.redis.get(key)
      return unless bytes
      evidence = JSON.parse(bytes)
      return unless evidence.is_a?(Hash) && evidence['version'] == 1
      return unless evidence['generation'].is_a?(String) && evidence['generation'].match?(/\A[0-9a-f]{32}\z/)
      %i[user_id request_key kind request_digest input_hash].each do |field|
        return unless evidence[field.to_s] == context[field]
      end
      raw_hash = evidence['raw_hash']
      return unless raw_hash.is_a?(String) && raw_hash.match?(/\A[0-9a-f]{40}\z/)
      cache_key = "unique-post-#{context[:user_id]}:#{raw_hash}"
      return unless evidence['cache_key'] == cache_key
      post_id = evidence['post_id']
      xid = evidence['xid']
      return unless post_id.is_a?(Integer) && post_id.positive?
      return unless xid.is_a?(String) && xid.match?(/\A[0-9]{1,20}\z/) && xid.to_i.between?(1, 18_446_744_073_709_551_615)
      return unless transaction_status(xid) == 'aborted'
      return if ::Post.unscoped.exists?(post_id)
      # Both values are compared atomically. A concurrent writer's replacement
      # must survive, even if it arrives after the SQL checks above.
      Discourse.redis.eval(REMOVE, keys: [key, cache_key].map { |value| Discourse.redis.namespace_key(value) },
        argv: [bytes, post_id.to_s])
    rescue JSON::ParserError
      # Malformed/unknown provenance cannot authorize a deletion.
      nil
    end

    def transaction_status(xid)
      # Savepoint isolates unsupported/aged status query errors from the user's
      # outer transaction. NULL, committed, and in-progress all fail closed.
      ::ActiveRecord::Base.transaction(requires_new: true) do
        ::ActiveRecord::Base.connection.select_value("SELECT pg_xact_status('#{xid}'::xid8)")
      end
    rescue ::ActiveRecord::StatementInvalid
      nil
    end

    module CreatorAdapter
      def initialize(user, opts)
        context = Thread.current[UniquePostRecovery::CONTEXT_KEY]
        if context && !context[:creator] && user.id == context[:user_id] &&
             context[:args].all? { |key, value| opts[key] == value }
          context[:creator] = self
        end
        super
      end

      def store_unique_post_key
        context = Thread.current[UniquePostRecovery::CONTEXT_KEY]
        return super unless context && context[:creator].equal?(self) && @post.user_id == context[:user_id]
        ttl = SiteSetting.unique_posts_mins.minutes.to_i
        return super unless ttl.positive?
        evidence = context.slice(:user_id, :request_key, :kind, :request_digest, :input_hash).merge(
          version: 1, generation: SecureRandom.hex(16), raw_hash: @post.raw_hash,
          cache_key: @post.unique_post_key, post_id: @post.id,
          xid: ::ActiveRecord::Base.connection.select_value('SELECT pg_current_xact_id()::text'),
        )
        Discourse.redis.eval(UniquePostRecovery::WRITE,
          keys: [@post.unique_post_key, UniquePostRecovery.marker_key(@post.user_id, context[:request_key])].map { |value| Discourse.redis.namespace_key(value) },
          argv: [ttl.to_s, @post.id.to_s, JSON.generate(evidence)])
      end
    end

    def install!
      ::PostCreator.prepend(CreatorAdapter) unless ::PostCreator.ancestors.include?(CreatorAdapter)
    end
  end
end
