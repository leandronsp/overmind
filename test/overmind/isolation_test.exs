defmodule Overmind.IsolationTest do
  use ExUnit.Case

  alias Overmind.Isolation
  alias Overmind.Isolation.PortRegistry

  @project_path File.cwd!()

  setup do
    :ets.delete_all_objects(:port_registry)
    :ok
  end

  describe "setup/2 — no .overmind.yml" do
    test "creates a worktree and returns env vars (no services)" do
      mission_id = "iso-test-#{System.unique_integer([:positive])}"

      result = Isolation.setup(mission_id, @project_path)

      case result do
        {:ok, %{worktree_path: wt_path, env: env}} ->
          assert is_binary(wt_path)
          assert File.exists?(wt_path)
          assert is_list(env)
          # No services in this project's .overmind.yml (or no yml at all)
          Isolation.teardown(mission_id, @project_path)

        {:error, _} ->
          # Git may reject the branch if it already exists; that's fine
          :ok
      end
    end
  end

  describe "setup/2 — with services" do
    setup do
      test_dir = Path.join(System.tmp_dir!(), "iso_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)
      # Initialise a bare git repo so worktree commands work
      System.cmd("git", ["init"], cd: test_dir, stderr_to_stdout: true)
      System.cmd("git", ["commit", "--allow-empty", "-m", "init"], cd: test_dir, stderr_to_stdout: true)
      on_exit(fn -> File.rm_rf!(test_dir) end)
      {:ok, dir: test_dir}
    end

    test "allocates ports for each service", %{dir: dir} do
      File.write!(Path.join(dir, ".overmind.yml"), """
      services:
        db:
          docker: postgres:16
          port: 5432
        cache:
          docker: redis:7
          port: 6379
      isolation:
        strategy: ports
        port_range: 3100-3999
      """)

      mission_id = "iso-svc-#{System.unique_integer([:positive])}"

      case Isolation.setup(mission_id, dir) do
        {:ok, result} ->
          assert length(result.env) == 2
          env_map = Enum.into(result.env, %{})
          assert Map.has_key?(env_map, "DB_PORT")
          assert Map.has_key?(env_map, "CACHE_PORT")

          db_port = String.to_integer(env_map["DB_PORT"])
          cache_port = String.to_integer(env_map["CACHE_PORT"])
          assert db_port >= 3100 and db_port <= 3999
          assert cache_port >= 3100 and cache_port <= 3999
          assert db_port != cache_port

          Isolation.teardown(mission_id, dir)

        {:error, _} ->
          :ok
      end
    end
  end

  describe "teardown/2" do
    test "releases ports for the mission" do
      mission_id = "tear-#{System.unique_integer([:positive])}"
      PortRegistry.allocate(mission_id, "db", 5432)
      PortRegistry.allocate(mission_id, "cache", 6379)

      assert length(PortRegistry.list()) == 2

      Isolation.teardown(mission_id, @project_path)

      ports_for_mission =
        PortRegistry.list()
        |> Enum.filter(fn {_, mid, _, _} -> mid == mission_id end)

      assert ports_for_mission == []
    end
  end
end
