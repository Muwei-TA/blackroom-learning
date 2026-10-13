# frozen_string_literal: true
module BlackroomLearning
  class Presenter
    PAGE_SIZE = 20
    def initialize(guardian:, current_user:)
      @guardian = guardian
      @current_user = current_user
    end

    def index(page: 0, username: nil, goal_id: nil)
      config = Access.configuration!(@guardian)
      scope = Goal.where(category_id: config[:category].id, flag_topic_id: config[:topic].id)
      if username.present?
        user = User.find_by(username_lower: username.downcase)
        raise Discourse::NotFound unless user
        scope = scope.where(user_id: user.id)
      end
      scope = scope.where(id: goal_id) if goal_id
      candidates = scope.order(id: :desc).offset(page * PAGE_SIZE).limit(PAGE_SIZE + 1).includes(:user, :receipts).to_a
      goals = candidates.first(PAGE_SIZE).filter_map { |goal| card(goal) }
      mine = scope_for_current(config).includes(:user, :receipts).order(id: :desc).limit(20).filter_map { |goal| card(goal) }
      {
        goals: goals, my_goals: mine, next_page: candidates.size > PAGE_SIZE ? page + 1 : nil,
        timezone: Policy::TIMEZONE, today: Policy.local_date(Time.current).iso8601,
        flag_topic_url: config[:topic].url, flag_topic_id: config[:topic].id,
        category_id: config[:category].id, summary: summary_for(config, username),
        can_create: Access.member_allowed?(@current_user) && @guardian.can_create_post_on_topic?(config[:topic]),
      }
    end

    def card(goal)
      snapshot = Snapshot.new(goal)
      owner = @current_user&.id == goal.user_id
      return unless snapshot.visible_to?(@guardian, owner: owner)
      return unless goal.user
      records = snapshot.visible_records(@guardian)
      # Apply the viewer's post visibility before deriving any user-facing totals.
      days = records.map { |record| Date.iso8601(record[:local_date]) }.uniq
      progress = Policy.progress(days: days, target_days: goal.target_days)
      {
        id: goal.id, name: goal.name, commitment: goal.commitment, username: goal.user.username,
        starts_on: goal.starts_on.iso8601, ends_on: goal.ends_on.iso8601,
        status: snapshot.status, progress: progress, streak: Policy.streaks(days: days, today: Policy.local_date(Time.current)),
        dates: days.sort.map(&:iso8601), records: records.first(50),
        owner: owner, can_checkin: owner && snapshot.status == 'active',
        can_cancel: owner && %w[active scheduled awaiting_approval unavailable].include?(snapshot.status),
        flag_url: snapshot.flag_usable? && @guardian.can_see?(snapshot.flag_post) ? snapshot.flag_post.url : nil,
        pending_checkins: owner ? snapshot.receipts.count { |receipt| receipt.kind == 'checkin' && snapshot.resolved(receipt)[:state] == 'queued' } : 0,
      }
    end

    def summary_for(config, username)
      user = username.present? ? User.find_by(username_lower: username.downcase) : @current_user
      return nil unless user
      cards = Goal.where(user_id: user.id, category_id: config[:category].id, flag_topic_id: config[:topic].id)
        .includes(:user, :receipts).filter_map { |goal| card(goal) }
      days = cards.flat_map { |item| item[:dates] }.uniq.map { |date| Date.iso8601(date) }
      xp = days.length * Policy::DAILY_XP
      {
        username: user.username, learning_days: days.length, xp: xp, level: Policy.level(xp: xp),
        streak: Policy.streaks(days: days, today: Policy.local_date(Time.current)),
        achievements: Policy.achievements(days: days, completed_goals: cards.count { |item| item[:progress][:completed] }),
      }
    end

    private

    def scope_for_current(config)
      Goal.where(user_id: @current_user.id, category_id: config[:category].id, flag_topic_id: config[:topic].id)
    end
  end
end
