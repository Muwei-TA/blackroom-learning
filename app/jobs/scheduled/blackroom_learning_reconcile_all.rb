# frozen_string_literal: true
module Jobs
  class BlackroomLearningReconcileAll < ::Jobs::Scheduled
    every 1.hour
    def execute(_args)
      return unless SiteSetting.blackroom_learning_enabled
      User.where(id: ::BlackroomLearning::Goal.select(:user_id)).find_each(batch_size: 100) do |user|
        Jobs.enqueue(:blackroom_learning_reconcile_user, user_id: user.id)
      end
    end
  end
end
