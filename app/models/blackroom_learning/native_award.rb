# frozen_string_literal: true
module BlackroomLearning
  class NativeAward < ::ActiveRecord::Base
    self.table_name = 'blackroom_learning_native_awards'
    validates :user_id, :code, :badge_id, :user_badge_id, presence: true
  end
end
