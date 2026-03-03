defmodule Overmind.Blueprint.ParserTest do
  use ExUnit.Case

  alias Overmind.Blueprint.Parser

  describe "parse/1" do
    test "empty content returns empty list" do
      assert {:ok, []} = Parser.parse("")
    end

    test "content with no agents section returns empty list" do
      toml = """
      [config]
      version = "1.0"
      """
      assert {:ok, []} = Parser.parse(toml)
    end

    test "parses a single agent with required fields" do
      toml = """
      [agents.fetcher]
      command = "echo hello"
      """
      {:ok, [spec]} = Parser.parse(toml)
      assert spec.name == "fetcher"
      assert spec.command == "echo hello"
    end

    test "defaults: raw provider, task type, never restart, no deps" do
      toml = """
      [agents.worker]
      command = "sleep 1"
      """
      {:ok, [spec]} = Parser.parse(toml)
      assert spec.provider == Overmind.Provider.Raw
      assert spec.type == :task
      assert spec.restart_policy == :never
      assert spec.depends_on == []
      assert spec.cwd == nil
    end

    test "parses provider: claude" do
      toml = """
      [agents.ai]
      command = "do something"
      provider = "claude"
      """
      {:ok, [spec]} = Parser.parse(toml)
      assert spec.provider == Overmind.Provider.Claude
    end

    test "parses type: session" do
      toml = """
      [agents.bot]
      command = ""
      type = "session"
      """
      {:ok, [spec]} = Parser.parse(toml)
      assert spec.type == :session
    end

    test "parses restart_policy: on-failure" do
      toml = """
      [agents.retrier]
      command = "flaky-cmd"
      restart_policy = "on-failure"
      """
      {:ok, [spec]} = Parser.parse(toml)
      assert spec.restart_policy == :on_failure
    end

    test "parses cwd field" do
      toml = """
      [agents.runner]
      command = "pwd"
      cwd = "/tmp"
      """
      {:ok, [spec]} = Parser.parse(toml)
      assert spec.cwd == "/tmp"
    end

    test "parses depends_on list" do
      toml = """
      [agents.processor]
      command = "process"
      depends_on = ["fetcher", "validator"]
      """
      {:ok, [spec]} = Parser.parse(toml)
      assert spec.depends_on == ["fetcher", "validator"]
    end

    test "parses multiple agents" do
      toml = """
      [agents.a]
      command = "cmd-a"

      [agents.b]
      command = "cmd-b"
      depends_on = ["a"]
      """
      {:ok, specs} = Parser.parse(toml)
      assert length(specs) == 2
      names = Enum.map(specs, & &1.name) |> Enum.sort()
      assert names == ["a", "b"]
    end

    test "invalid TOML returns error" do
      assert {:error, _} = Parser.parse("not valid toml ::::")
    end
  end
end
