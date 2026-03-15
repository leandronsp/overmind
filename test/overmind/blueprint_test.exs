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
    test "linear pipeline A→B→C spawns all in order" do
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

      assert {:ok, results} = Overmind.Blueprint.apply(path)
      assert length(results) == 3
      names = Enum.map(results, & &1.name)
      assert names == ["step1", "step2", "step3"]

      Enum.each(results, fn r ->
        assert r.status == :stopped
        assert r.exit_code == 0
        assert is_binary(r.id)
      end)
    end

    test "agent failure stops pipeline and reports error" do
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

      assert {:error, err} = Overmind.Blueprint.apply(path)
      assert err.agent == "bad_step"
      assert err.reason == :non_zero_exit
      assert length(err.completed) == 1
      assert hd(err.completed).name == "ok_step"
    end

    test "single agent with no deps works" do
      path = write_toml("""
      [agents.solo]
      command = "echo alone"
      """)

      assert {:ok, [result]} = Overmind.Blueprint.apply(path)
      assert result.name == "solo"
      assert result.status == :stopped
      assert result.exit_code == 0
    end

    test "sets parent on agents with depends_on" do
      path = write_toml("""
      [agents.parent_agent]
      command = "echo parent"

      [agents.child_agent]
      command = "echo child"
      depends_on = ["parent_agent"]
      """)

      assert {:ok, [parent, child]} = Overmind.Blueprint.apply(path)
      stored_parent = Overmind.Mission.Store.lookup_parent(child.id)
      assert stored_parent == parent.id
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
