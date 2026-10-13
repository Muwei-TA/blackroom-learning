# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../../lib/blackroom_learning/policy'
require_relative '../../app/services/blackroom_learning/snapshot'

# Tests the real projection lifecycle methods without constructing an ORM/database.
# Source validity and progress are tested separately in PolicyTest.
class LifecycleTest < Minitest::Test
  Plan = Struct.new(:cancelled_at, :completed_at, :starts_on, :ends_on, keyword_init: true)

  def snapshot(completed_at: nil, complete: false, cancelled_at: nil)
    value = BlackroomLearning::Snapshot.allocate
    value.instance_variable_set(:@goal, Plan.new(cancelled_at: cancelled_at, completed_at: completed_at,
      starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 30)))
    value.instance_variable_set(:@now, Time.iso8601('2026-10-13T12:00:00+08:00'))
    value.instance_variable_set(:@flag_state, 'published')
    value.define_singleton_method(:flag_usable?) { true }
    value.define_singleton_method(:progress) { { completed: complete } }
    value
  end

  def test_revoked_completion_does_not_reopen_a_finished_goal
    assert_equal 'ended', snapshot(completed_at: Time.utc(2026, 10, 12)).status
  end

  def test_finished_goal_does_not_take_a_second_active_slot_after_reversal
    refute snapshot(completed_at: Time.utc(2026, 10, 12)).occupies_slot?
  end

  def test_a_genuine_active_goal_still_blocks_a_second_goal
    assert_equal 'active', snapshot.status
    assert snapshot.occupies_slot?
  end

  def test_restored_sources_can_restore_completed_status_without_reopening
    assert_equal 'completed', snapshot(completed_at: Time.utc(2026, 10, 12), complete: true).status
  end

  def test_cancellation_stays_terminal
    assert_equal 'cancelled', snapshot(cancelled_at: Time.utc(2026, 10, 12)).status
    refute snapshot(cancelled_at: Time.utc(2026, 10, 12)).occupies_slot?
  end
end
