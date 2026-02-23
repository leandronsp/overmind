defmodule Overmind.Provider.RawTest do
  use ExUnit.Case

  alias Overmind.Provider.Raw

  describe "build_command/1" do
    test "wraps command with sh -c" do
      assert Raw.build_command("echo hello") == "sh -c 'echo hello'"
    end

    test "escapes single quotes" do
      assert Raw.build_command("echo 'hi'") == "sh -c 'echo '\\''hi'\\'''"
    end
  end

  describe "parse_line/1" do
    test "returns plain event with nil raw" do
      assert Raw.parse_line("hello") == {{:plain, "hello"}, nil}
    end

    test "handles empty string" do
      assert Raw.parse_line("") == {{:plain, ""}, nil}
    end
  end

  describe "format_for_logs/1" do
    test "plain event appends newline" do
      assert Raw.format_for_logs({:plain, "hello"}) == "hello\n"
    end
  end
end
