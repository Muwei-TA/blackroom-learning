# frozen_string_literal: true
module BlackroomLearning
  # A read-only projection of original receipts and CURRENT moderation state.
  # Never trusts a cached total or a client-provided publication timestamp.
  class Snapshot
    attr_reader :goal, :receipts, :days, :flag_post, :flag_state, :posts, :now

    def initialize(goal, now: Time.current)
      @goal = goal
      @now = now
      @receipts = goal.receipts.to_a
      @posts = {}
      @resolved = {}
      reviews = Reviewable.where(id: receipts.filter_map(&:reviewable_id)).index_by(&:id)
      ids = receipts.filter_map(&:post_id)
      reviews.each_value { |review| ids << review.target_id if review.approved? && review.target_type == 'Post' }
      @posts = Post.unscoped.where(id: ids.uniq).includes(:topic, :user).index_by(&:id)
      receipts.each { |receipt| @resolved[receipt.id] = resolve(receipt, reviews[receipt.reviewable_id]) }
      flag = receipts.find { |receipt| receipt.kind == 'flag' }
      @flag_state = flag ? @resolved.fetch(flag.id)[:state] : 'unavailable'
      @flag_post = flag && @resolved.fetch(flag.id)[:post]
      @days = Policy.effective_days(goal: policy_goal, sources: sources, now: now)
    end

    def resolved(receipt)
      @resolved.fetch(receipt.id)
    end

    def flag_usable?
      post = flag_post
      topic = post&.topic
      post && topic && post.user_id == goal.user_id && post.post_number > 1 &&
        post.topic_id == goal.flag_topic_id && post.post_type == Post.types[:regular] &&
        post.deleted_at.nil? && !post.hidden && post.raw.present? &&
        topic.deleted_at.nil? && topic.visible && topic.archetype == Archetype.default &&
        topic.category_id == goal.category_id && Access.member_allowed?(post.user)
    end

    def visible_to?(guardian, owner: false)
      topic = Topic.find_by(id: goal.flag_topic_id)
      return false unless topic && topic.category_id == goal.category_id && guardian.can_see?(topic)
      return true if owner
      flag_usable? && guardian.can_see?(flag_post)
    end

    def policy_goal
      {
        user_id: goal.user_id, category_id: goal.category_id, target_days: goal.target_days,
        starts_on: goal.starts_on, ends_on: goal.ends_on, cancelled_at: goal.cancelled_at,
        flag_visible: !!flag_usable?,
      }
    end

    def progress
      Policy.progress(days: days, target_days: goal.target_days)
    end

    def status
      return 'cancelled' if goal.cancelled_at
      return 'awaiting_approval' if flag_state == 'queued'
      return 'rejected' if flag_state == 'rejected'
      return 'unavailable' unless flag_usable?
      return 'completed' if progress[:completed]
      # Once finished, a moderation reversal changes progress but never opens a second active plan.
      return 'ended' if goal.completed_at
      today = Policy.local_date(now)
      return 'ended' if today > goal.ends_on
      today < goal.starts_on ? 'scheduled' : 'active'
    end

    def occupies_slot?
      return false if goal.cancelled_at || goal.completed_at || Policy.local_date(now) > goal.ends_on
      # Hidden/pending goals cannot be exploited to open a second overlapping goal.
      !%w[rejected completed].include?(status)
    end

    def sources
      receipts.select { |receipt| receipt.kind == 'checkin' }.map do |receipt|
        result = resolved(receipt)
        post = result[:post]
        topic = post&.topic
        {
          receipt_id: receipt.id, author_id: post&.user_id, category_id: topic&.category_id,
          topic_id: post&.topic_id, original_topic_id: receipt.original_topic_id || result[:original_topic_id],
          post_number: post&.post_number,
          post_type: post&.post_type == Post.types[:regular] ? 'regular' : 'other',
          topic_archetype: topic&.archetype, submitted_at: receipt.submitted_at,
          published: result[:state] == 'published' && !post.nil?,
          post_deleted: post.nil? || !post.deleted_at.nil?, post_hidden: post.nil? || post.hidden,
          topic_deleted: topic.nil? || !topic.deleted_at.nil?, topic_visible: !!topic&.visible,
          raw_present: post&.raw.present?, member_allowed: Access.member_allowed?(post&.user),
        }
      end
    end

    def visible_records(guardian)
      source_index = sources.to_h { |source| [source[:receipt_id], source] }
      receipts.filter_map do |receipt|
        next unless receipt.kind == 'checkin'
        result = resolved(receipt)
        post = result[:post]
        next unless post && !post.hidden && !post.deleted_at && guardian.can_see?(post)
        source = source_index[receipt.id]
        next unless source && Policy.source_eligible?(goal: policy_goal, source: source, now: now)
        { local_date: Policy.local_date(receipt.submitted_at).iso8601, url: post.url,
          title: post.topic.title, topic_id: post.topic_id }
      end.sort_by { |row| row[:local_date] }.reverse
    end

    private

    def resolve(receipt, review)
      # Once associated with a published post, retain the original topic ID even after a move.
      if receipt.post_id
        return { state: 'published', post: posts[receipt.post_id], original_topic_id: receipt.original_topic_id }
      end
      if review&.approved? && review.target_type == 'Post'
        post = posts[review.target_id]
        return { state: 'published', post: post, original_topic_id: receipt.original_topic_id || review.topic_id || post&.topic_id }
      end
      state = if review&.pending?
        'queued'
      elsif review && !review.approved?
        'rejected'
      else
        'unavailable'
      end
      { state: state, post: nil, original_topic_id: nil }
    end
  end
end
