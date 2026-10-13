# frozen_string_literal: true
module BlackroomLearning
  class XpEntry < ::ActiveRecord::Base
    self.table_name = 'blackroom_learning_xp_entries'
    validates :amount, :revision, :local_date, :reason, presence: true
    # Updates/deletes are not part of the application interface. User deletion still cascades in SQL.
    def readonly?
      persisted?
    end
  end
end
