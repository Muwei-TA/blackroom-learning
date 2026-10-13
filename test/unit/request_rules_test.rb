# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../../lib/blackroom_learning/policy'
require_relative '../../app/services/blackroom_learning/submissions'

class RequestRulesTest < Minitest::Test
  def test_missing_goal_fields_are_a_validation_error_not_a_server_exception
    assert_raises(BlackroomLearning::RuleError) do
      BlackroomLearning::Policy.validate_goal!(today: Date.new(2026, 10, 13))
    end
  end

  def test_missing_checkin_fields_can_reach_validation
    required = BlackroomLearning::Submissions.method(:checkin).parameters.select { |kind, _| kind == :keyreq }.map(&:last)
    assert_equal [:user, :guardian], required
  end

  def test_request_key_normalization
    uuid = 'ABCDEF12-1234-4234-8234-ABCDEF123456'
    assert_equal uuid.downcase, BlackroomLearning::Submissions.request_key!(uuid)
  end

  [nil, '', 'x', '../admin', ['abc'], 'a' * 1000].each_with_index do |key, index|
    define_method("test_rejects_invalid_request_key_#{index}") do
      assert_raises(BlackroomLearning::RuleError) { BlackroomLearning::Submissions.request_key!(key) }
    end
  end

  def test_digest_is_stable_across_parameter_order
    a = BlackroomLearning::Submissions.digest('flag', { name: '中文目标', days: '30' })
    b = BlackroomLearning::Submissions.digest('flag', { 'days' => '30', 'name' => '中文目标' })
    assert_equal a, b
    assert_match(/\A[0-9a-f]{64}\z/, a)
  end

  def test_digest_separates_operations_and_payloads
    a = BlackroomLearning::Submissions.digest('flag', { name: '目标 A' })
    refute_equal a, BlackroomLearning::Submissions.digest('checkin', { name: '目标 A' })
    refute_equal a, BlackroomLearning::Submissions.digest('flag', { name: '目标 B' })
  end
end
