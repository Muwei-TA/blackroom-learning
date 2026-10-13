# frozen_string_literal: true
# name: blackroom-learning
# about: Member-owned learning goals, topic-based daily check-ins and reversible learning rewards.
# version: 0.1.0-dev
# authors: BlackRoom contributors
# required_version: 2026.10.0-latest

enabled_site_setting :blackroom_learning_enabled
register_asset 'stylesheets/blackroom-learning.scss'

module ::BlackroomLearning
  PLUGIN_NAME = 'blackroom-learning'
end

require_relative 'lib/blackroom_learning/policy'
require_relative 'lib/blackroom_learning/engine'

after_initialize do
  %w[goal receipt checkin_day xp_entry native_award].each do |name|
    require_relative "app/models/blackroom_learning/#{name}"
  end
  %w[access snapshot native_awards reconcile_user submissions presenter].each do |name|
    require_relative "app/services/blackroom_learning/#{name}"
  end
  require_relative 'app/controllers/blackroom_learning/learning_controller'
  require_relative 'app/jobs/regular/blackroom_learning_reconcile_user'
  require_relative 'app/jobs/scheduled/blackroom_learning_reconcile_all'
  require_relative 'lib/blackroom_learning/callbacks'
  BlackroomLearning::Callbacks.install!
  Discourse::Application.routes.append do
    mount ::BlackroomLearning::Engine, at: '/learning'
  end
end
