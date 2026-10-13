# frozen_string_literal: true
require 'minitest/autorun'
require 'date'
require 'time'
require_relative '../../lib/blackroom_learning/policy' if File.exist?(File.expand_path('../../lib/blackroom_learning/policy.rb', __dir__))

class PolicyTest < Minitest::Test
  def setup
    assert defined?(BlackroomLearning::Policy), 'Missing learning policy implementation'
    @policy = BlackroomLearning::Policy
    @today = Date.new(2026, 10, 13)
    @now = Time.iso8601('2026-10-13T12:00:00+08:00')
  end

  def valid_goal_input
    { name: '绘画基础练习', commitment: '每天完成一张练习并记录一个问题', starts_on: '2026-10-13',
      ends_on: '2026-11-11', target_days: '30', today: @today }
  end

  def goal(**changes)
    { user_id: 10, category_id: 50, starts_on: Date.new(2026, 10, 1),
      ends_on: Date.new(2026, 10, 30), target_days: 30, flag_visible: true,
      cancelled_at: nil }.merge(changes)
  end

  def source(**changes)
    { author_id: 10, category_id: 50, topic_id: 201, original_topic_id: 201,
      post_number: 1, post_type: 'regular', topic_archetype: 'regular',
      submitted_at: Time.iso8601('2026-10-13T11:00:00+08:00'),
      published: true, post_deleted: false, post_hidden: false, topic_deleted: false,
      topic_visible: true, raw_present: true, member_allowed: true }.merge(changes)
  end

  def test_normalizes_goal_and_keeps_inclusive_window
    result = @policy.validate_goal!(**valid_goal_input)
    assert_equal 30, result[:target_days]
    assert_equal @today, result[:starts_on]
    assert_equal 30, (result[:ends_on] - result[:starts_on]).to_i + 1
  end

  def test_single_day_goal
    result = @policy.validate_goal!(**valid_goal_input.merge(target_days: 1, ends_on: '2026-10-13'))
    assert_equal 1, result[:target_days]
  end

  def test_buffer_window_allowed
    assert_equal 20, @policy.validate_goal!(**valid_goal_input.merge(target_days: 20))[:target_days]
  end

  def test_strips_names
    assert_equal '学习目标', @policy.validate_goal!(**valid_goal_input.merge(name: '  学习目标  '))[:name]
  end

  {
    negative_days: { target_days: -1 }, zero_days: { target_days: 0 },
    float_days: { target_days: 1.9 }, exponent_days: { target_days: '1e2' },
    trailing_digits: { target_days: '30abc' }, missing_days: { target_days: nil },
    many_days: { target_days: 367 }, days_longer_than_window: { target_days: 31 },
    reverse_window: { ends_on: '2026-10-12' }, past_start: { starts_on: '2026-10-12' },
    bad_date: { starts_on: '2026-02-30' }, loose_date: { starts_on: '2026-1-1' },
    datetime_as_date: { starts_on: '2026-10-13T00:00:00Z' },
    missing_name: { name: '' }, huge_name: { name: 'a' * 121 },
    tiny_commitment: { commitment: '学' }, huge_commitment: { commitment: 'a' * 2001 },
    too_long_window: { ends_on: '2027-10-14' },
  }.each do |name, changes|
    define_method("test_rejects_#{name}") do
      assert_raises(BlackroomLearning::RuleError) { @policy.validate_goal!(**valid_goal_input.merge(changes)) }
    end
  end

  def test_midnight_uses_shanghai_not_utc
    assert_equal Date.new(2026, 10, 13), @policy.local_date(Time.iso8601('2026-10-12T16:00:00Z'))
    assert_equal Date.new(2026, 10, 12), @policy.local_date(Time.iso8601('2026-10-12T15:59:59Z'))
  end

  def test_timezone_offset_equivalence
    assert_equal @policy.local_date(Time.iso8601('2026-10-13T00:30:00+08:00')),
                 @policy.local_date(Time.iso8601('2026-10-12T09:30:00-07:00'))
  end

  def test_timestamp_must_be_a_server_time_object
    assert_raises(BlackroomLearning::RuleError) { @policy.local_date('2026-10-13') }
  end

  def test_valid_source
    assert @policy.source_eligible?(goal: goal, source: source, now: @now)
  end

  {
    wrong_author: { author_id: 11 }, wrong_category: { category_id: 51 },
    reply: { post_number: 2 }, system_post: { post_type: 'small_action' },
    private_message: { topic_archetype: 'private_message' },
    queue: { published: false }, deleted_post: { post_deleted: true },
    hidden_post: { post_hidden: true }, deleted_topic: { topic_deleted: true },
    unlisted_topic: { topic_visible: false }, empty_raw: { raw_present: false },
    bot: { member_allowed: false }, moved_post: { topic_id: 202 },
    future_submission: { submitted_at: Time.iso8601('2026-10-13T14:00:00+08:00') },
    before_start: { submitted_at: Time.iso8601('2026-09-30T12:00:00+08:00') },
  }.each do |name, changes|
    define_method("test_excludes_#{name}") do
      refute @policy.source_eligible?(goal: goal, source: source(**changes), now: @now)
    end
  end

  def test_hidden_flag_cannot_generate_progress
    refute @policy.source_eligible?(goal: goal(flag_visible: false), source: source, now: @now)
  end

  def test_expired_goal_keeps_prior_valid_submission
    old = source(submitted_at: Time.iso8601('2026-10-02T23:00:00+08:00'))
    assert @policy.source_eligible?(goal: goal(ends_on: Date.new(2026, 10, 2)), source: old, now: @now)
  end

  def test_after_deadline_excluded
    refute @policy.source_eligible?(goal: goal(ends_on: Date.new(2026, 10, 12)), source: source, now: @now)
  end

  def test_cancellation_preserves_earlier_submissions
    assert @policy.source_eligible?(goal: goal(cancelled_at: @now), source: source, now: @now)
    refute @policy.source_eligible?(goal: goal(cancelled_at: @now - 7200), source: source, now: @now)
  end

  def test_approval_time_does_not_move_submission_date
    late_approved = source(submitted_at: Time.iso8601('2026-10-12T23:59:59+08:00'))
    assert_equal [Date.new(2026, 10, 12)], @policy.effective_days(goal: goal, sources: [late_approved], now: @now)
  end

  def test_multiple_sources_same_day_count_once
    sources = [source, source(topic_id: 202, original_topic_id: 202)]
    assert_equal [@today], @policy.effective_days(goal: goal, sources: sources, now: @now)
  end

  def test_deleting_one_source_preserves_day_until_all_invalid
    sources = [source(post_deleted: true), source(topic_id: 202, original_topic_id: 202)]
    assert_equal [@today], @policy.effective_days(goal: goal, sources: sources, now: @now)
    sources.last[:post_deleted] = true
    assert_empty @policy.effective_days(goal: goal, sources: sources, now: @now)
    sources.first[:post_deleted] = false
    assert_equal [@today], @policy.effective_days(goal: goal, sources: sources, now: @now)
  end

  def test_progress_12_out_of_30_is_40_percent
    result = @policy.progress(days: (1..12).map { |d| Date.new(2026, 10, d) }, target_days: 30)
    assert_equal({ completed_days: 12, target_days: 30, percent: 40.0, completed: false }, result)
  end

  def test_progress_deduplicates_and_caps_percentage_not_history
    days = (1..12).map { |d| Date.new(2026, 10, d) }
    result = @policy.progress(days: days + days, target_days: 10)
    assert_equal 12, result[:completed_days]
    assert_equal 100.0, result[:percent]
    assert result[:completed]
  end

  def test_empty_progress
    assert_equal 0.0, @policy.progress(days: [], target_days: 30)[:percent]
  end

  def test_progress_rejects_zero_divisor
    assert_raises(BlackroomLearning::RuleError) { @policy.progress(days: [], target_days: 0) }
  end

  def test_current_streak_does_not_break_before_today_ends
    dates = [@today - 3, @today - 2, @today - 1]
    assert_equal({ current: 3, longest: 3 }, @policy.streaks(days: dates, today: @today))
  end

  def test_longest_streak_handles_gap_duplicates_and_future
    dates = [@today - 8, @today - 7, @today - 6, @today - 2, @today, @today, @today + 1]
    assert_equal({ current: 1, longest: 3 }, @policy.streaks(days: dates, today: @today))
  end

  def test_broken_streak
    assert_equal({ current: 0, longest: 2 }, @policy.streaks(days: [@today - 3, @today - 2], today: @today))
    assert_equal({ current: 0, longest: 0 }, @policy.streaks(days: [], today: @today))
  end

  def test_reward_is_user_day_based_and_idempotent
    assert_equal({ @today => 10 }, @policy.reward_changes(days: [@today, @today], balances: {}))
    assert_empty @policy.reward_changes(days: [@today], balances: { @today => 10 })
  end

  def test_reward_reversal_and_restore
    assert_equal({ @today => -10 }, @policy.reward_changes(days: [], balances: { @today => 10 }))
    assert_equal({ @today => 10 }, @policy.reward_changes(days: [@today], balances: { @today => 0 }))
  end

  def test_reconciliation_corrects_duplicate_old_credit
    assert_equal({ @today => -10 }, @policy.reward_changes(days: [@today], balances: { @today => 20 }))
  end

  def test_learning_levels
    assert_equal 1, @policy.level(xp: 0)
    assert_equal 1, @policy.level(xp: 90)
    assert_equal 2, @policy.level(xp: 100)
    assert_equal 4, @policy.level(xp: 300)
  end

  def test_achievements_follow_real_records
    assert_empty @policy.achievements(days: [], completed_goals: 0)
    assert_equal ['first_checkin'], @policy.achievements(days: [@today], completed_goals: 0)
    days = (0...30).map { |n| @today - n }
    assert_equal %w[first_checkin streak_7 total_30 goal_complete], @policy.achievements(days: days, completed_goals: 1)
    assert_equal ['first_checkin'], @policy.achievements(days: [@today], completed_goals: 0)
  end
end
