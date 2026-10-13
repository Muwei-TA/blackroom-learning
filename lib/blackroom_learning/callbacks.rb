# frozen_string_literal: true
module BlackroomLearning
  module Callbacks
    module_function

    def enqueue_for(relation)
      return unless SiteSetting.blackroom_learning_enabled
      relation.distinct.pluck(:user_id).each do |user_id|
        Jobs.enqueue(:blackroom_learning_reconcile_user, user_id: user_id)
      end
    end

    def install!
      # after_commit avoids jobs seeing rolled-back or half-written submissions.
      Post.after_commit do
        if SiteSetting.blackroom_learning_enabled
          BlackroomLearning::Callbacks.enqueue_for(BlackroomLearning::Receipt.where(post_id: id))
        end
      end
      Topic.after_commit do
        if SiteSetting.blackroom_learning_enabled
          ids = BlackroomLearning::Goal.where(flag_topic_id: id).select(:id)
          relation = BlackroomLearning::Receipt.where(original_topic_id: id)
            .or(BlackroomLearning::Receipt.where(goal_id: ids))
          BlackroomLearning::Callbacks.enqueue_for(relation)
        end
      end
      ReviewableQueuedPost.after_commit do
        if SiteSetting.blackroom_learning_enabled
          BlackroomLearning::Callbacks.enqueue_for(BlackroomLearning::Receipt.where(reviewable_id: id))
        end
      end
      Category.after_commit do
        if SiteSetting.blackroom_learning_enabled
          BlackroomLearning::Goal.where(category_id: id).distinct.pluck(:user_id).each do |user_id|
            Jobs.enqueue(:blackroom_learning_reconcile_user, user_id: user_id)
          end
        end
      end
    end
  end
end
