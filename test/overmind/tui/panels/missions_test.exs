defmodule Overmind.TUI.Panels.MissionsTest do
  use ExUnit.Case

  alias Overmind.TUI.Panels.Missions

  @sample_missions [
    %{"id" => "abc123", "name" => "brave-fox", "status" => "running", "type" => "task", "command" => "sleep 100"},
    %{"id" => "def456", "name" => "lazy-cat", "status" => "crashed", "type" => "session", "command" => "echo hello"},
    %{"id" => "ghi789", "name" => "fast-wolf", "status" => "stopped", "type" => "task", "command" => "ls"}
  ]

  describe "render/3 — structure" do
    test "renders a header row" do
      output = Missions.render(@sample_missions, 0, 80)
      assert output =~ "NAME"
      assert output =~ "STATUS"
      assert output =~ "TYPE"
      assert output =~ "COMMAND"
    end

    test "renders all missions" do
      output = Missions.render(@sample_missions, 0, 80)
      assert output =~ "brave-fox"
      assert output =~ "lazy-cat"
      assert output =~ "fast-wolf"
    end

    test "empty missions list renders only header" do
      output = Missions.render([], 0, 80)
      assert output =~ "NAME"
      refute output =~ "brave-fox"
    end
  end

  describe "render/3 — selection" do
    test "selected row has reverse-video ANSI code" do
      output = Missions.render(@sample_missions, 0, 80)
      # \e[7m is reverse video; selected row should contain it before mission name
      lines = String.split(output, "\r\n")
      # second line is first data row (after header)
      selected_line = Enum.at(lines, 1)
      assert selected_line =~ "\e[7m"
    end

    test "non-selected rows do not have reverse-video code" do
      output = Missions.render(@sample_missions, 0, 80)
      lines = String.split(output, "\r\n")
      # third line is second row (lazy-cat, not selected)
      unselected_line = Enum.at(lines, 2)
      refute unselected_line =~ "\e[7m"
    end

    test "selection can be on last item" do
      output = Missions.render(@sample_missions, 2, 80)
      lines = String.split(output, "\r\n")
      last_line = Enum.at(lines, 3)
      assert last_line =~ "\e[7m"
    end
  end

  describe "render/3 — status colors" do
    test "running missions use green ANSI code" do
      output = Missions.render(@sample_missions, 1, 80)
      # select index 1 (lazy-cat/crashed), so running (brave-fox) is unselected
      lines = String.split(output, "\r\n")
      running_line = Enum.at(lines, 1)
      # \e[32m is green
      assert running_line =~ "\e[32m"
    end

    test "crashed missions use red ANSI code" do
      output = Missions.render(@sample_missions, 0, 80)
      lines = String.split(output, "\r\n")
      crashed_line = Enum.at(lines, 2)
      # \e[31m is red
      assert crashed_line =~ "\e[31m"
    end

    test "stopped missions use yellow ANSI code" do
      output = Missions.render(@sample_missions, 0, 80)
      lines = String.split(output, "\r\n")
      stopped_line = Enum.at(lines, 3)
      # \e[33m is yellow
      assert stopped_line =~ "\e[33m"
    end
  end

  describe "render/3 — long commands" do
    test "commands longer than 40 chars are truncated" do
      long_cmd = String.duplicate("a", 50)
      missions = [%{"id" => "x", "name" => "n", "status" => "running", "type" => "task", "command" => long_cmd}]
      output = Missions.render(missions, 0, 80)
      assert output =~ "..."
      refute output =~ long_cmd
    end
  end
end
