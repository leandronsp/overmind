defmodule Overmind.Blueprint.RunnerTest do
  use ExUnit.Case

  alias Overmind.Blueprint.Runner
  alias Overmind.Mission.Store

  setup do
    Overmind.Test.MissionHelper.cleanup_missions()
    :ok
  end

  describe "empty pipeline" do
    test "starts, registers in ETS, completes as stopped with exit_code 0" do
      id = Overmind.Mission.generate_id()
      name = Overmind.Mission.Name.generate()

      {:ok, pid} = start_runner(id: id, name: name, specs: [])
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000

      assert {:exited, :stopped, _, _} = Store.lookup(id)
      assert Store.lookup_type(id) == :blueprint
      assert Store.lookup_exit_code(id) == 0
      assert Store.lookup_name(id) == name
    end
  end

  describe "get_logs while alive" do
    test "returns logs from running pipeline" do
      id = Overmind.Mission.generate_id()

      {:ok, pid} = start_runner(
        id: id,
        name: "test-runner",
        specs: [make_spec("sleeper", "sleep 2")]
      )

      # Give worker time to start the mission
      Process.sleep(100)

      {:ok, logs} = Store.safe_call(pid, :get_logs)
      assert is_binary(logs)

      # Clean up
      Store.safe_call(pid, {:stop, :sigterm})
    end
  end

  describe "single agent pipeline" do
    test "runs agent and completes as stopped" do
      id = Overmind.Mission.generate_id()

      {:ok, pid} = start_runner(
        id: id,
        name: "test-runner",
        specs: [make_spec("greeter", "echo hello")]
      )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000

      assert {:exited, :stopped, _, _} = Store.lookup(id)
      assert Store.lookup_exit_code(id) == 0

      logs = Store.stored_logs(id)
      assert logs =~ "greeter"
      assert logs =~ "stopped"
    end
  end

  describe "agent failure stops pipeline" do
    test "crashes runner when agent exits non-zero" do
      id = Overmind.Mission.generate_id()

      {:ok, pid} = start_runner(
        id: id,
        name: "test-runner",
        specs: [
          make_spec("ok_step", "echo fine"),
          make_spec("bad_step", "sh -c 'exit 1'")
        ]
      )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000

      assert {:exited, :crashed, _, _} = Store.lookup(id)
      assert Store.lookup_exit_code(id) == 1

      logs = Store.stored_logs(id)
      assert logs =~ "bad_step"
    end
  end

  describe "multi-agent pipeline with parent hierarchy" do
    test "runs A->B->C and sets parents" do
      id = Overmind.Mission.generate_id()

      {:ok, pid} = start_runner(
        id: id,
        name: "test-runner",
        specs: [
          make_spec("step_a", "echo a"),
          %{make_spec("step_b", "echo b") | depends_on: ["step_a"]},
          %{make_spec("step_c", "echo c") | depends_on: ["step_b"]}
        ]
      )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3000

      assert {:exited, :stopped, _, _} = Store.lookup(id)
      assert Store.lookup_exit_code(id) == 0

      # Verify parent hierarchy
      b_id = Store.find_by_name("step_b")
      a_id = Store.find_by_name("step_a")
      assert Store.lookup_parent(b_id) == a_id
    end
  end

  describe "stop and kill" do
    test "stop gracefully stops runner" do
      id = Overmind.Mission.generate_id()

      {:ok, pid} = start_runner(
        id: id,
        name: "test-runner",
        specs: [make_spec("slow", "sleep 30")]
      )

      Process.sleep(100)
      ref = Process.monitor(pid)

      {:ok, :ok} = Store.safe_call(pid, {:stop, :sigterm})
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      assert {:exited, :stopped, _, _} = Store.lookup(id)
      assert Store.lookup_exit_code(id) == 0
    end

    test "kill removes runner from ETS" do
      id = Overmind.Mission.generate_id()

      {:ok, pid} = start_runner(
        id: id,
        name: "test-runner",
        specs: [make_spec("slow", "sleep 30")]
      )

      Process.sleep(100)
      ref = Process.monitor(pid)

      {:ok, :ok} = Store.safe_call(pid, {:kill, :sigkill})
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      assert Store.lookup(id) == :not_found
    end
  end

  # Helpers

  defp start_runner(opts) do
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    specs = Keyword.fetch!(opts, :specs)

    spec = {Runner, id: id, name: name, filename: "test.toml", specs: specs}
    DynamicSupervisor.start_child(Overmind.MissionSupervisor, spec)
  end

  defp make_spec(name, command) do
    %{
      name: name,
      command: command,
      provider: Overmind.Provider.Raw,
      type: :task,
      cwd: nil,
      restart_policy: :never,
      depends_on: []
    }
  end
end
