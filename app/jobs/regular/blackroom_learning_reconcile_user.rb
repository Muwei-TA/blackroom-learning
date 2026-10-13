# frozen_string_literal: true
module Jobs
  class BlackroomLearningReconcileUser < ::Jobs::Base
    def execute(args)
      ::BlackroomLearning::ReconcileUser.call(args[:user_id])
    end
  end
end
