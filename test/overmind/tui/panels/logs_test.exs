defmodule Overmind.TUI.Panels.LogsTest do
  use ExUnit.Case

  alias Overmind.TUI.Panels.Logs

  describe "render/4 — header" do
    test "shows mission id when provided" do
      output = Logs.render("", "brave-fox", 80, 24)
      assert output =~ "brave-fox"
    end

    test "shows generic header when mission is nil" do
      output = Logs.render("", nil, 80, 24)
      assert output =~ "Logs"
      refute output =~ "nil"
    end

    test "header includes navigation hint" do
      output = Logs.render("", "m1", 80, 24)
      assert output =~ "[t]"
    end
  end

  describe "render/4 — body" do
    test "empty logs shows no-logs message" do
      output = Logs.render("", "m1", 80, 24)
      assert output =~ "no logs yet"
    end

    test "non-empty logs are rendered" do
      output = Logs.render("line one\nline two\nline three", "m1", 80, 24)
      assert output =~ "line one"
      assert output =~ "line two"
      assert output =~ "line three"
    end

    test "only tail lines are shown when log exceeds height" do
      many_lines = Enum.map_join(1..100, "\n", fn i -> "line #{i}" end)
      # height=10 means max 7 body lines (height - 3)
      output = Logs.render(many_lines, "m1", 80, 10)
      refute output =~ "line 1\r\n"
      assert output =~ "line 100"
    end
  end
end
