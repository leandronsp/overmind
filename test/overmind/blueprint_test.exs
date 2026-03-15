defmodule Overmind.BlueprintTest do
  use ExUnit.Case

  setup do
    Overmind.Test.MissionHelper.cleanup_missions()
    :ok
  end

  describe "agents/1" do
    test "returns agent specs from valid file" do
      path = write_toml("""
      [agents.greeter]
      command = "echo hello"
      """)

      assert {:ok, [spec]} = Overmind.Blueprint.agents(path)
      assert spec.name == "greeter"
      assert spec.command == "echo hello"
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = Overmind.Blueprint.agents("/nonexistent/file.toml")
    end
  end

  describe "apply/1" do
    test "returns id and name immediately" do
      path = write_toml("""
      [agents.greeter]
      command = "echo hello"
      """)

      assert {:ok, %{id: id, name: name}} = Overmind.Blueprint.apply(path)
      assert is_binary(id)
      assert String.length(id) == 8
      assert is_binary(name)
    end

    test "linear pipeline A->B->C completes via wait" do
      path = write_toml("""
      [agents.step1]
      command = "echo one"

      [agents.step2]
      command = "echo two"
      depends_on = ["step1"]

      [agents.step3]
      command = "echo three"
      depends_on = ["step2"]
      """)

      assert {:ok, %{id: id}} = Overmind.Blueprint.apply(path)
      assert {:ok, result} = Overmind.wait(id)
      assert result.status == :stopped
      assert result.exit_code == 0

      # All agents exist in ETS
      assert Overmind.Mission.Store.find_by_name("step1")
      assert Overmind.Mission.Store.find_by_name("step2")
      assert Overmind.Mission.Store.find_by_name("step3")
    end

    test "agent failure crashes runner" do
      path = write_toml("""
      [agents.ok_step]
      command = "echo fine"

      [agents.bad_step]
      command = "sh -c 'exit 1'"
      depends_on = ["ok_step"]

      [agents.never_runs]
      command = "echo nope"
      depends_on = ["bad_step"]
      """)

      assert {:ok, %{id: id}} = Overmind.Blueprint.apply(path)
      assert {:ok, result} = Overmind.wait(id)
      assert result.status == :crashed
      assert result.exit_code == 1
    end

    test "sets parent on agents with depends_on" do
      path = write_toml("""
      [agents.parent_agent]
      command = "echo parent"

      [agents.child_agent]
      command = "echo child"
      depends_on = ["parent_agent"]
      """)

      assert {:ok, %{id: runner_id}} = Overmind.Blueprint.apply(path)
      assert {:ok, _} = Overmind.wait(runner_id)

      parent_id = Overmind.Mission.Store.find_by_name("parent_agent")
      child_id = Overmind.Mission.Store.find_by_name("child_agent")
      # Root agent's parent is the runner
      assert Overmind.Mission.Store.lookup_parent(parent_id) == runner_id
      # Dependent agent's parent is its dependency
      assert Overmind.Mission.Store.lookup_parent(child_id) == parent_id
    end

    test "logs contain pipeline output" do
      path = write_toml("""
      [agents.greeter]
      command = "echo hello"
      """)

      assert {:ok, %{id: id}} = Overmind.Blueprint.apply(path)
      assert {:ok, _} = Overmind.wait(id)
      assert {:ok, logs} = Overmind.logs(id)
      assert logs =~ "greeter"
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = Overmind.Blueprint.apply("/nonexistent.toml")
    end

    test "returns error for cycle" do
      path = write_toml("""
      [agents.a]
      command = "echo a"
      depends_on = ["b"]

      [agents.b]
      command = "echo b"
      depends_on = ["a"]
      """)

      assert {:error, :cycle} = Overmind.Blueprint.apply(path)
    end
  end

  defp write_toml(content) do
    path = Path.join(System.tmp_dir!(), "blueprint_test_#{:rand.uniform(1_000_000)}.toml")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
