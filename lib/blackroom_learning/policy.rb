# frozen_string_literal: true
require 'date'
require 'time'

module BlackroomLearning
  class RuleError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code.to_s
      super(@code)
    end
  end

  # Deterministic business rules. No database, clock lookup, network or side effects.
  module Policy
    TIMEZONE = 'Asia/Shanghai'
    UTC_OFFSET = '+08:00'
    DAILY_XP = 10
    XP_PER_LEVEL = 100
    MAX_DAYS = 366

    module_function

    def date!(value)
      return value if value.instance_of?(Date)
      raise RuleError, :invalid_date unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(value)
    rescue Date::Error
      raise RuleError, :invalid_date
    end

    def day_count!(value)
      valid = value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A[1-9]\d{0,2}\z/))
      raise RuleError, :invalid_target_days unless valid
      count = value.to_i
      raise RuleError, :invalid_target_days unless (1..MAX_DAYS).cover?(count)
      count
    end

    def validate_goal!(name: nil, commitment: nil, starts_on: nil, ends_on: nil, target_days: nil, today:)
      raise RuleError, :invalid_name unless name.is_a?(String) && (2..120).cover?(name.strip.length)
      unless commitment.is_a?(String) && (8..2000).cover?(commitment.strip.length)
        raise RuleError, :invalid_commitment
      end
      starts = date!(starts_on)
      ends = date!(ends_on)
      current = date!(today)
      count = day_count!(target_days)
      window = (ends - starts).to_i + 1
      raise RuleError, :start_in_past if starts < current
      raise RuleError, :invalid_window unless (1..MAX_DAYS).cover?(window) && count <= window
      {
        name: name.strip, commitment: commitment.strip,
        starts_on: starts, ends_on: ends, target_days: count,
      }
    end

    def local_date(timestamp)
      raise RuleError, :invalid_timestamp unless timestamp.is_a?(Time)
      timestamp.getlocal(UTC_OFFSET).to_date
    end

    def source_eligible?(goal:, source:, now:)
      return false unless goal[:flag_visible] && source[:published] && source[:member_allowed]
      return false unless source[:author_id] == goal[:user_id] && source[:author_id].to_i.positive?
      return false unless source[:category_id] == goal[:category_id]
      return false unless source[:topic_id] == source[:original_topic_id]
      return false unless source[:post_number] == 1 && source[:post_type] == 'regular'
      return false unless source[:topic_archetype] == 'regular'
      return false if source[:post_deleted] || source[:post_hidden] || source[:topic_deleted]
      return false unless source[:topic_visible] && source[:raw_present]
      submitted = source[:submitted_at]
      return false unless submitted.is_a?(Time) && submitted <= now
      return false if goal[:cancelled_at] && submitted > goal[:cancelled_at]
      (goal[:starts_on]..goal[:ends_on]).cover?(local_date(submitted))
    end

    def effective_days(goal:, sources:, now:)
      sources.filter_map do |source|
        local_date(source[:submitted_at]) if source_eligible?(goal: goal, source: source, now: now)
      end.uniq.sort
    end

    def progress(days:, target_days:)
      target = day_count!(target_days)
      count = days.map { |day| date!(day) }.uniq.length
      {
        completed_days: count,
        target_days: target,
        percent: (Rational([count, target].min * 100, target)).round(1).to_f,
        completed: count >= target,
      }
    end

    def streaks(days:, today:)
      current_day = date!(today)
      dates = days.map { |day| date!(day) }.uniq.select { |day| day <= current_day }.sort
      run = 0
      longest = 0
      previous = nil
      dates.each do |day|
        run = previous && day == previous + 1 ? run + 1 : 1
        longest = [longest, run].max
        previous = day
      end
      current = dates.last && dates.last >= current_day - 1 ? run : 0
      { current: current, longest: longest }
    end

    # A caller persists nonzero deltas, never overwrites the audit ledger.
    # Serialize callers with a user row lock and commit days+ledger atomically.
    def reward_changes(days:, balances:)
      dates = days.map { |day| date!(day) }.uniq
      current = balances.to_h { |day, xp| [date!(day), Integer(xp)] }
      (dates | current.keys).sort.each_with_object({}) do |day, changes|
        desired = dates.include?(day) ? DAILY_XP : 0
        delta = desired - current.fetch(day, 0)
        changes[day] = delta unless delta.zero?
      end
    end

    def level(xp:)
      [Integer(xp), 0].max / XP_PER_LEVEL + 1
    end

    def achievements(days:, completed_goals:)
      dates = days.map { |day| date!(day) }.uniq.sort
      earned = []
      earned << 'first_checkin' unless dates.empty?
      earned << 'streak_7' if !dates.empty? && streaks(days: dates, today: dates.last)[:longest] >= 7
      earned << 'total_30' if dates.length >= 30
      earned << 'goal_complete' if Integer(completed_goals).positive?
      earned
    end
  end
end
