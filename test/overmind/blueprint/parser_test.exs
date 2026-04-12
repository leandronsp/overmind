defmodule Overmind.Blueprint.ParserTest do
  use ExUnit.Case

  alias Overmind.Blueprint.Parser

  describe "parse/1" do
    test "parses valid TOML with one agent" do
      toml = """
      [agents.greeter]
      command = "echo hello"
      """

      assert {:ok, [spec]} = Parser.parse(toml)
      assert spec.name == "greeter"
      assert spec.command == "echo hello"
    end

    test "returns empty list when no agents section" do
      assert {:ok, []} = Parser.parse("")
    end

    test "returns error on invalid TOML" do
      assert {:error, {:invalid_toml, _}} = Parser.parse("[[[invalid")
    end

    test "missing command returns error" do
      toml = """
      [agents.broken]
      depends_on = []
      """

      assert {:error, {:missing_command, "broken"}} = Parser.parse(toml)
    end

    test "unknown dependency returns error" do
      toml = """
      [agents.worker]
      command = "echo hi"
      depends_on = ["ghost"]
      """

      assert {:error, {:unknown_dependency, "worker", "ghost"}} = Parser.parse(toml)
    end

    test "defaults: provider=Raw, type=task, cwd=nil, model=nil, restart=never, depends_on=[]" do
      toml = """
      [agents.minimal]
      command = "echo hi"
      """

      assert {:ok, [spec]} = Parser.parse(toml)
      assert spec.provider == Overmind.Provider.Raw
      assert spec.type == :task
      assert spec.cwd == nil
      assert spec.model == nil
      assert spec.restart_policy == :never
      assert spec.depends_on == []
    end

    test "parses model field" do
      toml = """
      [agents.researcher]
      command = "echo research"
      provider = "claude"
      model = "haiku"
      """

      assert {:ok, [spec]} = Parser.parse(toml)
      assert spec.model == "haiku"
    end

    test "parses all optional fields" do
      toml = """
      [agents.worker]
      command = "echo hi"
      provider = "claude"
      type = "session"
      cwd = "/tmp"
      restart = "on-failure"
      depends_on = []
      """

      assert {:ok, [spec]} = Parser.parse(toml)
      assert spec.provider == Overmind.Provider.Claude
      assert spec.type == :session
      assert spec.cwd == "/tmp"
      assert spec.restart_policy == :on_failure
    end

    test "parses multiple agents with valid dependencies" do
      toml = """
      [agents.setup]
      command = "echo setup"

      [agents.worker]
      command = "echo work"
      depends_on = ["setup"]
      """

      assert {:ok, specs} = Parser.parse(toml)
      assert length(specs) == 2
    end
  end
end
