defmodule Overmind.Ritual.SchedulerTest do
  use ExUnit.Case

  alias Overmind.Ritual.Scheduler

  describe "cron_matches?/2" do
    test "* * * * * matches any datetime" do
      dt = ~U[2024-03-15 14:30:00Z]
      assert Scheduler.cron_matches?("* * * * *", dt)
    end

    test "matches specific minute" do
      dt = ~U[2024-03-15 14:30:00Z]
      assert Scheduler.cron_matches?("30 * * * *", dt)
      refute Scheduler.cron_matches?("31 * * * *", dt)
    end

    test "matches specific hour" do
      dt = ~U[2024-03-15 14:30:00Z]
      assert Scheduler.cron_matches?("* 14 * * *", dt)
      refute Scheduler.cron_matches?("* 15 * * *", dt)
    end

    test "matches specific day of month" do
      dt = ~U[2024-03-15 14:30:00Z]
      assert Scheduler.cron_matches?("* * 15 * *", dt)
      refute Scheduler.cron_matches?("* * 16 * *", dt)
    end

    test "matches specific month" do
      dt = ~U[2024-03-15 14:30:00Z]
      assert Scheduler.cron_matches?("* * * 3 *", dt)
      refute Scheduler.cron_matches?("* * * 4 *", dt)
    end

    # 2024-03-15 is a Friday = DOW 5 in standard cron (Sun=0, Mon=1, ..., Fri=5, Sat=6)
    test "matches specific day of week" do
      dt = ~U[2024-03-15 14:30:00Z]
      assert Scheduler.cron_matches?("* * * * 5", dt)
      refute Scheduler.cron_matches?("* * * * 6", dt)
    end

    test "Sunday maps to DOW 0" do
      # 2024-03-17 is a Sunday
      dt = ~U[2024-03-17 10:00:00Z]
      assert Scheduler.cron_matches?("* * * * 0", dt)
      refute Scheduler.cron_matches?("* * * * 1", dt)
    end

    test "returns false for invalid cron expression" do
      dt = ~U[2024-03-15 14:30:00Z]
      refute Scheduler.cron_matches?("invalid", dt)
      refute Scheduler.cron_matches?("1 2 3", dt)
    end

    test "all fields match together" do
      # 2024-03-15 14:30 is Friday
      dt = ~U[2024-03-15 14:30:00Z]
      assert Scheduler.cron_matches?("30 14 15 3 5", dt)
      refute Scheduler.cron_matches?("30 14 15 3 6", dt)
    end
  end
end
