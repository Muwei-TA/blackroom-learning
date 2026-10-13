# frozen_string_literal: true
require 'minitest/autorun'
require 'yaml'

# Packaging/static safety checks; these are NOT Rails integration tests.
class PackageContractTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def read(path)
    full_path = File.join(ROOT, path)
    assert File.file?(full_path), "Missing package file: #{path}"
    File.read(full_path)
  end

  def test_safe_defaults
    config = YAML.safe_load(read('config/settings.yml')).fetch('plugins')
    assert_equal false, config.fetch('blackroom_learning_enabled').fetch('default')
    assert_equal 0, config.fetch('blackroom_learning_category_id').fetch('default')
    assert_equal 0, config.fetch('blackroom_learning_flag_topic_id').fetch('default')
  end

  def test_submissions_use_review_pipeline_without_bypass
    body = read('app/services/blackroom_learning/submissions.rb')
    assert_includes body, '::NewPostManager.new(user,'
    refute_match(/skip_(?:validations|guardian|events)\s*:/, body)
    refute_includes body, 'Discourse.system_user'
    assert_includes body, 'user.with_lock'
    assert_includes body, 'submitted_at: Time.current'
    assert_includes body, 'request_digest'
  end

  def test_schema_contains_independent_deduplication_constraints
    body = read('db/migrate/20261013000000_create_blackroom_learning.rb')
    assert_includes body, '[:user_id, :request_key]'
    assert_includes body, '[:goal_id, :local_date]'
    assert_includes body, '[:user_id, :local_date, :revision]'
    assert_includes body, 'unique: true'
    assert_includes body, 'add_check_constraint'
  end

  def test_controller_checks_login_permission_and_rate_limits
    body = read('app/controllers/blackroom_learning/learning_controller.rb')
    assert_includes body, 'requires_plugin'
    assert_includes body, 'requires_login'
    assert_includes body, 'Access.configuration!'
    assert_includes body, 'RateLimiter'
    refute_includes body, 'skip_before_action'
    refute_includes body, 'permit!'
  end

  def test_reconcile_serializes_ledger_changes
    body = read('app/services/blackroom_learning/reconcile_user.rb')
    assert_includes body, 'user.with_lock'
    assert_includes body, 'XpEntry.create!'
    assert_includes body, 'Policy.reward_changes'
    refute_match(/XpEntry\.(?:delete_all|destroy_all|update_all)/, body)
  end

  def test_presenter_has_audience_checks
    body = read('app/services/blackroom_learning/presenter.rb')
    assert_includes body, 'visible_to?'
    assert_includes body, 'guardian'
    refute_includes body, 'User.all'
  end

  def test_native_awards_do_not_revoke_unowned_badges
    body = read('app/services/blackroom_learning/native_awards.rb')
    assert_includes body, 'NativeAward.where(user_id: user.id)'
    assert_includes body, 'UserBadge.find_by(id: claim.user_badge_id, user_id: user.id'
    assert_includes body, 'read_restricted'
    assert_includes body, 'suppress_notification: true'
  end

  def test_events_are_after_commit_and_have_repair_job
    body = read('lib/blackroom_learning/callbacks.rb')
    assert_includes body, 'after_commit'
    assert_includes read('app/jobs/scheduled/blackroom_learning_reconcile_all.rb'), 'every 1.hour'
  end
end
