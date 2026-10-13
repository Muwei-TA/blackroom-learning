# frozen_string_literal: true
require 'digest'
require 'json'

module BlackroomLearning
  class SubmissionError < RuleError
    attr_reader :messages
    def initialize(messages)
      @messages = messages
      super(:post_rejected)
    end
  end

  module Submissions
    module_function

    def request_key!(key)
      unless key.is_a?(String) && key.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        raise RuleError, :invalid_request_key
      end
      key.downcase
    end

    def digest(kind, payload)
      Digest::SHA256.hexdigest(JSON.generate([kind, payload.transform_keys(&:to_s).sort.to_h]))
    end

    def existing!(user, key, fingerprint)
      receipt = Receipt.find_by(user_id: user.id, request_key: key)
      raise RuleError, :request_conflict if receipt && receipt.request_digest != fingerprint
      receipt
    end

    def goal(user:, guardian:, attributes:, request_key:, timing: {})
      Access.member!(user)
      config = Access.configuration!(guardian)
      key = request_key!(request_key)
      fingerprint = digest('flag', attributes)
      receipt = nil
      user.with_lock do
        receipt = existing!(user, key, fingerprint)
        if receipt.nil?
          unless guardian.can_create_post_on_topic?(config[:topic])
            raise Discourse::InvalidAccess
          end
          existing_goals = Goal.where(user_id: user.id).where(cancelled_at: nil).where('ends_on >= ?', Policy.local_date(Time.current))
          prior = existing_goals.map { |goal| Snapshot.new(goal) }
          raise RuleError, :active_goal_exists if prior.any?(&:occupies_slot?)
          # Seal completed predecessors under the same lock, including delayed reconciliation.
          prior.each do |snapshot|
            if snapshot.progress[:completed] && snapshot.goal.completed_at.nil?
              snapshot.goal.update!(completed_at: Time.current)
            end
          end
          values = Policy.validate_goal!(**attributes.symbolize_keys, today: Policy.local_date(Time.current))
          goal = Goal.create!(**values, user_id: user.id, category_id: config[:category].id, flag_topic_id: config[:topic].id)
          receipt = Receipt.create!(goal_id: goal.id, user_id: user.id, kind: 'flag', request_key: key,
            request_digest: fingerprint, submitted_at: Time.current)
          raw = I18n.t('blackroom_learning.flag_body', name: goal.name, commitment: goal.commitment,
            starts_on: goal.starts_on.iso8601, ends_on: goal.ends_on.iso8601, target_days: goal.target_days)
          raw += "\n\n[#{I18n.t('blackroom_learning.view_progress')}](#{Discourse.base_url}/learning?goal_id=#{goal.id})"
          perform!(user, receipt, { topic_id: goal.flag_topic_id, raw: raw }, timing)
        end
      end
      ReconcileUser.call(user.id)
      receipt.reload
    end

    def checkin(user:, guardian:, goal_id: nil, title: nil, raw: nil, request_key: nil, timing: {})
      Access.member!(user)
      Access.configuration!(guardian)
      key = request_key!(request_key)
      fingerprint = digest('checkin', { goal_id: goal_id.to_s, title: title, raw: raw })
      receipt = nil
      user.with_lock do
        receipt = existing!(user, key, fingerprint)
        if receipt.nil?
          goal = Access.goal!(goal_id, user, guardian)
          snapshot = Snapshot.new(goal)
          raise RuleError, :goal_not_active unless snapshot.status == 'active'
          category = Category.find_by(id: goal.category_id)
          raise Discourse::InvalidAccess unless guardian.can_create_topic_on_category?(category)
          raise RuleError, :invalid_post unless title.is_a?(String) && raw.is_a?(String)
          raise RuleError, :invalid_post if title.length > 255 || raw.length > 100_000
          receipt = Receipt.create!(goal_id: goal.id, user_id: user.id, kind: 'checkin', request_key: key,
            request_digest: fingerprint, submitted_at: Time.current)
          perform!(user, receipt, { title: title, raw: raw, category: goal.category_id, archetype: Archetype.default }, timing)
        end
      end
      ReconcileUser.call(user.id)
      receipt.reload
    end

    def cancel(user:, guardian:, goal_id:)
      user.with_lock do
        goal = Access.goal!(goal_id, user, guardian)
        # Ending a plan never edits its denominator or deletes prior effort.
        unless goal.cancelled_at
          raise RuleError, :goal_already_ended if %w[completed ended rejected].include?(Snapshot.new(goal).status)
          goal.update!(cancelled_at: Time.current)
        end
      end
      ReconcileUser.call(user.id)
    end

    def perform!(user, receipt, args, timing = {})
      # These flags activate ordinary first-post checks; no guardian/approval bypass.
      context = %w[typing_duration_msecs composer_open_duration_msecs].to_h do |key|
        value = Integer(timing[key] || timing[key.to_sym] || 0, exception: false)
        [key.to_sym, (value || 0).clamp(0, 86_400_000)]
      end
      result = ::NewPostManager.new(user, args.merge(context).merge(first_post_checks: true)).perform
      raise SubmissionError, result.errors.full_messages unless result.success?
      if result.post
        receipt.update!(post_id: result.post.id, original_topic_id: result.post.topic_id, state: 'published')
      elsif result.reviewable
        receipt.update!(reviewable_id: result.reviewable.id, state: 'queued')
      else
        raise RuleError, :unexpected_post_result
      end
    end
  end
end
