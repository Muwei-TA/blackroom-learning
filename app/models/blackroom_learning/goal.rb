# frozen_string_literal: true
module BlackroomLearning
  class Goal < ::ActiveRecord::Base
    self.table_name = 'blackroom_learning_goals'
    belongs_to :user, class_name: '::User'
    has_many :receipts, class_name: 'BlackroomLearning::Receipt', dependent: :destroy
    has_many :checkin_days, class_name: 'BlackroomLearning::CheckinDay', dependent: :destroy
    validates :name, :commitment, :starts_on, :ends_on, presence: true
    validates :target_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 366 }
    attr_readonly :user_id, :category_id, :flag_topic_id, :starts_on, :ends_on, :target_days, :timezone, :rule_version
  end
end
