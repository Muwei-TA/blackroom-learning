# frozen_string_literal: true
module BlackroomLearning
  class CheckinDay < ::ActiveRecord::Base
    self.table_name = 'blackroom_learning_checkin_days'
    belongs_to :goal, class_name: 'BlackroomLearning::Goal'
    validates :local_date, presence: true
  end
end
