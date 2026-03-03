defmodule Overmind.BlueprintTest do
  use ExUnit.Case

  alias Overmind.Blueprint

  setup do
    Overmind.Test.MissionHelper.cleanup_missions()
    :ok
  end

  describe "agents/1" do
    test "returns specs from a valid blueprint file" do
      toml = """
      [agents.worker]
      command = "echo working"
      """
      path = write_temp_toml(toml)
      {:ok, specs} = Blueprint.agents(path)
      assert length(specs) == 1
      assert hd(specs).name == "worker"
    end

    test "returns error for nonexistent file" do
      assert {:error, :enoent} = Blueprint.agents("/nonexistent/blueprint.toml")
    end

    test "returns error for invalid TOML" do
      path = write_temp_toml("not valid ::::")
      assert {:error, _} = Blueprint.agents(path)
    end
  end

  describe "apply/1" do
    test "spawns missions from blueprint and returns ids" do
      toml = """
      [agents.task-a]
      command = "true"

      [agents.task-b]
      command = "true"
      """
      path = write_temp_toml(toml)
      {:ok, results} = Blueprint.apply(path)
      assert length(results) == 2
      assert Enum.all?(results, fn r -> is_binary(r.id) and is_binary(r.name) end)
    end

    test "respects dependency ordering — dependent runs after dependency" do
      toml = """
      [agents.step-a]
      command = "true"

      [agents.step-b]
      command = "true"
      depends_on = ["step-a"]
      """
      path = write_temp_toml(toml)
      {:ok, results} = Blueprint.apply(path)
      names = Enum.map(results, & &1.name)
      a_idx = Enum.find_index(names, &(&1 == "step-a"))
      b_idx = Enum.find_index(names, &(&1 == "step-b"))
      assert a_idx < b_idx
    end

    test "returns error for nonexistent file" do
      assert {:error, :enoent} = Blueprint.apply("/nonexistent/blueprint.toml")
    end

    test "returns error for cycle in blueprint" do
      toml = """
      [agents.x]
      command = "true"
      depends_on = ["y"]

      [agents.y]
      command = "true"
      depends_on = ["x"]
      """
      path = write_temp_toml(toml)
      assert {:error, :cycle} = Blueprint.apply(path)
    end
  end

  defp write_temp_toml(content) do
    path = Path.join(System.tmp_dir!(), "blueprint_test_#{:rand.uniform(100_000)}.toml")
    File.write!(path, content)
    path
  end
end
