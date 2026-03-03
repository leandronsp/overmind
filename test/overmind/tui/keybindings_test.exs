defmodule Overmind.TUI.KeybindingsTest do
  use ExUnit.Case

  alias Overmind.TUI.Keybindings

  describe "handle/1 — navigation" do
    test "j navigates down" do
      assert Keybindings.handle("j") == :nav_down
    end

    test "k navigates up" do
      assert Keybindings.handle("k") == :nav_up
    end
  end

  describe "handle/1 — panel switching" do
    test "l shows logs" do
      assert Keybindings.handle("l") == :show_logs
    end

    test "Enter shows logs" do
      assert Keybindings.handle("\r") == :show_logs
    end

    test "t shows missions" do
      assert Keybindings.handle("t") == :show_missions
    end

    test "? shows help" do
      assert Keybindings.handle("?") == :show_help
    end
  end

  describe "handle/1 — quit" do
    test "q quits" do
      assert Keybindings.handle("q") == :quit
    end

    test "Ctrl+C quits" do
      assert Keybindings.handle("\x03") == :quit
    end

    test "EOF quits" do
      assert Keybindings.handle(:eof) == :quit
    end
  end

  describe "handle/1 — refresh and unknown" do
    test "r refreshes" do
      assert Keybindings.handle("r") == :refresh
    end

    test "unknown keys are ignored" do
      assert Keybindings.handle("z") == :unknown
      assert Keybindings.handle("x") == :unknown
      assert Keybindings.handle("\t") == :unknown
    end
  end
end
