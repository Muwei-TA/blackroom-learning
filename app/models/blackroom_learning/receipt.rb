# frozen_string_literal: true
module BlackroomLearning
  class Receipt < ::ActiveRecord::Base
    self.table_name = 'blackroom_learning_receipts'
    belongs_to :goal, class_name: 'BlackroomLearning::Goal'
    belongs_to :user, class_name: '::User'
    belongs_to :post, class_name: '::Post', optional: true
    validates :kind, inclusion: { in: %w[flag checkin] }
    validates :request_key, :request_digest, :submitted_at, presence: true
    attr_readonly :user_id, :goal_id, :kind, :request_key, :request_digest, :submitted_at
  end
end
