# frozen_string_literal: true
module BlackroomLearning
  module ReconcileUser
    module_function

    def call(user_id)
      return unless SiteSetting.blackroom_learning_enabled
      user = User.find_by(id: user_id)
      return unless user
      user.with_lock do
        goals = Goal.where(user_id: user.id).includes(:receipts).to_a
        snapshots = goals.map { |goal| Snapshot.new(goal) }
        snapshots.each do |snapshot|
          if snapshot.progress[:completed] && snapshot.goal.completed_at.nil?
            snapshot.goal.update!(completed_at: Time.current)
          end
          snapshot.receipts.each do |receipt|
            result = snapshot.resolved(receipt)
            changes = { state: result[:state] }
            if result[:post] && receipt.post_id.nil?
              changes[:post_id] = result[:post].id
              changes[:original_topic_id] = result[:original_topic_id]
            end
            receipt.assign_attributes(changes)
            receipt.save! if receipt.changed?
          end
          rows = CheckinDay.where(goal_id: snapshot.goal.id).index_by(&:local_date)
          (snapshot.days | rows.keys).each do |date|
            row = rows[date] || CheckinDay.new(goal_id: snapshot.goal.id, user_id: user.id, local_date: date)
            row.valid_day = snapshot.days.include?(date)
            row.save! if row.new_record? || row.changed?
          end
        end
        dates = snapshots.flat_map(&:days).uniq
        balances = XpEntry.where(user_id: user.id).group(:local_date).sum(:amount)
        Policy.reward_changes(days: dates, balances: balances).each do |date, delta|
          revision = XpEntry.where(user_id: user.id, local_date: date).maximum(:revision).to_i + 1
          XpEntry.create!(user_id: user.id, local_date: date, revision: revision, amount: delta,
            reason: delta.positive? ? 'valid_learning_day' : 'learning_day_invalidated', created_at: Time.current)
        end
        earned = Policy.achievements(days: dates, completed_goals: snapshots.count { |s| s.progress[:completed] })
        # Optional cosmetic bridge must not roll back core bookkeeping if another plugin breaks badges.
        begin
          ActiveRecord::Base.transaction(requires_new: true) { NativeAwards.sync(user, earned: earned, goals: goals) }
        rescue StandardError => error
          Rails.logger.warn("[blackroom-learning] native badge sync failed: #{error.class.name}")
        end
      end
    end
  end
end
