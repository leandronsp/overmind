defmodule OvermindTest do
  use ExUnit.Case

  setup do
    Overmind.Test.MissionHelper.cleanup_missions()
    :ok
  end

  describe "run/1" do
    test "returns {:ok, id} and mission is visible in ETS" do
      {:ok, id} = Overmind.run("sleep 60")

      assert String.length(id) == 8
      [{^id, pid, "sleep 60", :running, _}] = :ets.lookup(:overmind_missions, id)
      assert is_pid(pid)
    end

    test "error for empty command" do
      assert {:error, :empty_command} = Overmind.run("")
    end
  end

  describe "run/2 with provider" do
    test "provider stores original command in ETS" do
      {:ok, id} = Overmind.run("echo hello", Overmind.Provider.TestClaude)
      [{^id, pid, "echo hello", _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end

    test "error for empty command with provider" do
      assert {:error, :empty_command} = Overmind.run("", Overmind.Provider.Claude)
    end
  end

  describe "run/2 with keyword opts" do
    test "accepts provider: option" do
      {:ok, id} = Overmind.run("echo opts", provider: Overmind.Provider.TestClaude)
      [{^id, pid, "echo opts", _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end

    test "accepts type: :task (default)" do
      {:ok, id} = Overmind.run("sleep 60", type: :task)
      assert String.length(id) == 8
    end

    test "accepts type: :session with empty command" do
      {:ok, id} = Overmind.run("", type: :session)
      assert String.length(id) == 8
    end

    test "rejects unknown type" do
      assert {:error, :invalid_type} = Overmind.run("echo hi", type: :bogus)
    end

    test "backward compat: atom second arg treated as provider" do
      {:ok, id} = Overmind.run("echo compat", Overmind.Provider.Raw)
      [{^id, _pid, "echo compat", _, _}] = :ets.lookup(:overmind_missions, id)
    end

    test "empty opts defaults to Raw provider and task type" do
      {:ok, id} = Overmind.run("sleep 60", [])
      assert String.length(id) == 8
    end
  end

  describe "run/2 with name" do
    test "name option sets agent name" do
      {:ok, id} = Overmind.run("sleep 60", name: "my-agent")
      assert Overmind.Mission.Store.lookup_name(id) == "my-agent"
    end

    test "auto-generates name when not provided" do
      {:ok, id} = Overmind.run("sleep 60")
      name = Overmind.Mission.Store.lookup_name(id)
      assert name != nil
      assert Regex.match?(~r/^[a-z]+-[a-z]+$/, name)
    end
  end

  describe "run/2 with restart opts" do
    test "accepts restart_policy option" do
      {:ok, id} = Overmind.run("sleep 60", restart_policy: :on_failure)
      assert Overmind.Mission.Store.lookup_restart_policy(id) == :on_failure
    end

    test "rejects invalid restart_policy" do
      assert {:error, :invalid_restart_policy} = Overmind.run("sleep 60", restart_policy: :bogus)
    end

    test "accepts activity_timeout option" do
      {:ok, _id} = Overmind.run("sleep 60", activity_timeout: 30)
    end
  end

  describe "run/2 with cwd" do
    test "cwd option runs command in specified directory" do
      {:ok, id} = Overmind.run("pwd", cwd: "/tmp")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, logs} = Overmind.logs(id)
      assert logs =~ "tmp"
    end
  end

  describe "ps/0" do
    test "empty list when no missions" do
      assert Overmind.ps() == []
    end

    test "returns mission info with uptime, type, restart_count, parent, children" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(10)

      [mission] = Overmind.ps()
      assert mission.id == id
      assert mission.command == "sleep 60"
      assert mission.status == :running
      assert mission.type == :task
      assert is_integer(mission.uptime)
      assert mission.uptime >= 0
      assert mission.restart_count == 0
      assert mission.parent == nil
      assert mission.children == 0
    end

    test "includes name in mission info" do
      {:ok, id} = Overmind.run("sleep 60", name: "ps-test")
      Process.sleep(10)

      [mission] = Overmind.ps()
      assert mission.id == id
      assert mission.name == "ps-test"
    end

    test "includes naturally exited missions" do
      {:ok, id} = Overmind.run("true")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      missions = Overmind.ps()
      assert Enum.any?(missions, fn m -> m.id == id and m.status == :stopped end)
    end

    test "does not include raw_events tuples" do
      {:ok, id} = Overmind.run("echo test")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      missions = Overmind.ps()
      assert Enum.all?(missions, fn m -> is_binary(m.id) end)
      assert Enum.any?(missions, fn m -> m.id == id end)
    end
  end

  describe "run/2 with parent" do
    test "accepts parent option for existing mission" do
      {:ok, parent_id} = Overmind.run("sleep 60")
      {:ok, child_id} = Overmind.run("sleep 60", parent: parent_id)

      assert Overmind.Mission.Store.lookup_parent(child_id) == parent_id
    end

    test "rejects nonexistent parent" do
      assert {:error, :parent_not_found} = Overmind.run("sleep 60", parent: "nonexist")
    end

    test "resolves parent by name" do
      {:ok, parent_id} = Overmind.run("sleep 60", name: "parent-test")
      {:ok, child_id} = Overmind.run("sleep 60", parent: "parent-test")

      assert Overmind.Mission.Store.lookup_parent(child_id) == parent_id
    end
  end

  describe "wait/2" do
    test "blocks until mission exits and returns status" do
      {:ok, id} = Overmind.run("sh -c 'sleep 0.3; exit 0'")

      assert {:ok, %{status: :stopped, exit_code: 0}} = Overmind.wait(id)
    end

    test "resolves by name" do
      {:ok, _id} = Overmind.run("sh -c 'sleep 0.3; exit 0'", name: "wait-test")

      assert {:ok, %{status: :stopped}} = Overmind.wait("wait-test")
    end

    test "error for unknown mission" do
      assert {:error, :not_found} = Overmind.wait("nonexist")
    end

    test "timeout returns error" do
      {:ok, id} = Overmind.run("sleep 60")

      assert {:error, :timeout} = Overmind.wait(id, 100)
    end
  end

  describe "info/1" do
    test "returns full info for running mission" do
      {:ok, id} = Overmind.run("sleep 60", name: "info-full", cwd: "/tmp",
        restart_policy: :on_failure, activity_timeout: 30)
      Process.sleep(50)

      {:ok, info} = Overmind.info(id)
      assert info.id == id
      assert info.name == "info-full"
      assert info.status == :running
      assert is_integer(info.os_pid)
      assert info.os_pid > 0
      assert info.type == :task
      assert info.cwd == "/tmp"
      assert info.restart_policy == :on_failure
      assert info.restart_count == 0
    end

    test "returns nil os_pid for exited mission" do
      {:ok, id} = Overmind.run("true")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, info} = Overmind.info(id)
      assert info.status == :stopped
      assert info.os_pid == nil
    end

    test "resolves by name" do
      {:ok, _id} = Overmind.run("sleep 60", name: "info-test")
      Process.sleep(50)

      {:ok, info} = Overmind.info("info-test")
      assert info.status == :running
      assert is_integer(info.os_pid)
    end

    test "error for unknown mission" do
      assert {:error, :not_found} = Overmind.info("nonexist")
    end
  end

  describe "logs/1" do
    test "returns logs from running mission" do
      {:ok, id} = Overmind.run("sh -c 'echo running; sleep 60'")
      Process.sleep(100)

      {:ok, logs} = Overmind.logs(id)
      assert logs =~ "running"
    end

    test "returns logs from dead mission" do
      {:ok, id} = Overmind.run("echo dead")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, logs} = Overmind.logs(id)
      assert logs =~ "dead"
    end

    test "error for unknown ID" do
      assert {:error, :not_found} = Overmind.logs("nonexist")
    end
  end

  describe "raw_events/1" do
    test "returns empty list for raw provider mission" do
      {:ok, id} = Overmind.run("echo hello")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, events} = Overmind.raw_events(id)
      assert events == []
    end

    test "error for unknown ID" do
      assert {:error, :not_found} = Overmind.raw_events("nonexist")
    end
  end

  describe "send/2" do
    test "sends message to session mission" do
      {:ok, id} = Overmind.run("", type: :session)
      Process.sleep(50)

      assert :ok = Overmind.send(id, "hello")
      Process.sleep(100)

      {:ok, logs} = Overmind.logs(id)
      assert logs =~ "[human] hello"
      assert logs =~ "hello\n"
    end

    test "error for task mission" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      assert {:error, :not_session} = Overmind.send(id, "hello")
    end

    test "error for unknown mission" do
      assert {:error, :not_found} = Overmind.send("nonexist", "hello")
    end
  end

  describe "stop/1" do
    test "stops a running mission, mission stays in ETS as :stopped" do
      {:ok, id} = Overmind.run("sleep 60")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)

      assert :ok = Overmind.stop(id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      [{^id, _, _, :stopped, _}] = :ets.lookup(:overmind_missions, id)
    end

    test "error for unknown mission" do
      assert {:error, :not_found} = Overmind.stop("nonexist")
    end

    test "error for already stopped mission" do
      {:ok, id} = Overmind.run("true")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      assert {:error, :not_running} = Overmind.stop(id)
    end
  end

  describe "kill/1" do
    test "force-kills a running mission and removes from ETS" do
      {:ok, id} = Overmind.run("sleep 60")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)

      assert :ok = Overmind.kill(id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      assert :ets.lookup(:overmind_missions, id) == []
    end

    test "works on SIGTERM-resistant processes" do
      {:ok, id} = Overmind.run("sh -c 'trap \"\" TERM; sleep 60'")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)

      assert :ok = Overmind.kill(id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      assert :ets.lookup(:overmind_missions, id) == []
    end

    test "kills a stopped mission and removes from ETS" do
      {:ok, id} = Overmind.run("true")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      assert :ok = Overmind.kill(id)
      assert :ets.lookup(:overmind_missions, id) == []
    end

    test "error for unknown mission" do
      assert {:error, :not_found} = Overmind.kill("nonexist")
    end
  end

  describe "kill_cascade/1" do
    test "kills parent and children" do
      {:ok, parent_id} = Overmind.run("sleep 60")
      {:ok, child_id} = Overmind.run("sleep 60", parent: parent_id)
      Process.sleep(50)

      assert :ok = Overmind.kill_cascade(parent_id)
      Process.sleep(50)

      assert :ets.lookup(:overmind_missions, parent_id) == []
      assert :ets.lookup(:overmind_missions, child_id) == []
    end

    test "resolves by name" do
      {:ok, parent_id} = Overmind.run("sleep 60", name: "cascade-parent")
      {:ok, child_id} = Overmind.run("sleep 60", parent: parent_id)
      Process.sleep(50)

      assert :ok = Overmind.kill_cascade("cascade-parent")
      Process.sleep(50)

      assert :ets.lookup(:overmind_missions, child_id) == []
    end

    test "kill without cascade leaves children running" do
      {:ok, parent_id} = Overmind.run("sleep 60")
      [{^parent_id, ppid, _, _, _}] = :ets.lookup(:overmind_missions, parent_id)
      {:ok, child_id} = Overmind.run("sleep 60", parent: parent_id)
      Process.sleep(50)

      ref = Process.monitor(ppid)
      assert :ok = Overmind.kill(parent_id)
      assert_receive {:DOWN, ^ref, :process, ^ppid, :normal}, 500

      # Child still alive
      assert {:running, _, _, _} = Overmind.Mission.Store.lookup(child_id)
    end

    test "error for unknown mission" do
      assert {:error, :not_found} = Overmind.kill_cascade("nonexist")
    end
  end

  describe "name resolution" do
    test "logs by name" do
      {:ok, id} = Overmind.run("echo byname", name: "test-logs")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, logs} = Overmind.logs("test-logs")
      assert logs =~ "byname"
    end

    test "stop by name" do
      {:ok, id} = Overmind.run("sleep 60", name: "test-stop")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)

      assert :ok = Overmind.stop("test-stop")
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "kill by name" do
      {:ok, id} = Overmind.run("sleep 60", name: "test-kill")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)

      assert :ok = Overmind.kill("test-kill")
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end
  end

  describe "children/1" do
    test "returns child missions" do
      {:ok, parent_id} = Overmind.run("sleep 60", name: "parent-ch")
      {:ok, child_id} = Overmind.run("sleep 60", parent: parent_id)

      children = Overmind.children(parent_id)
      assert length(children) == 1
      assert hd(children).id == child_id
    end

    test "returns empty list for no children" do
      {:ok, id} = Overmind.run("sleep 60")
      assert Overmind.children(id) == []
    end

    test "resolves parent by name" do
      {:ok, _parent_id} = Overmind.run("sleep 60", name: "parent-by-name")
      {:ok, child_id} = Overmind.run("sleep 60", parent: "parent-by-name")

      children = Overmind.children("parent-by-name")
      assert length(children) == 1
      assert hd(children).id == child_id
    end
  end

  describe "format_ps/1" do
    test "formats empty list with header only" do
      output = Overmind.format_ps([])
      assert output =~ "ID"
      assert output =~ "NAME"
      assert output =~ "TYPE"
      assert output =~ "STATUS"
      assert output =~ "RESTARTS"
      assert output =~ "PARENT"
      assert output =~ "CHILDREN"
      assert output =~ "UPTIME"
      assert output =~ "COMMAND"
    end

    test "formats missions with columns" do
      missions = [
        %{id: "abc12345", name: "bold-arc", type: :task, status: :running, restart_count: 0, parent: nil, children: 0, uptime: 30, command: "sleep 60"}
      ]

      output = Overmind.format_ps(missions)
      assert output =~ "abc12345"
      assert output =~ "bold-arc"
      assert output =~ "task"
      assert output =~ "running"
      assert output =~ "30s"
      assert output =~ "sleep 60"
      assert output =~ "-"
    end

    test "formats missions with parent" do
      missions = [
        %{id: "abc12345", name: "bold-arc", type: :task, status: :running, restart_count: 0, parent: "p1234567", children: 2, uptime: 30, command: "sleep 60"}
      ]

      output = Overmind.format_ps(missions)
      assert output =~ "p1234567"
      assert output =~ "2"
    end

    test "formats missions with restarts" do
      missions = [
        %{id: "abc12345", name: "bold-arc", type: :task, status: :restarting, restart_count: 3, parent: nil, children: 0, uptime: 30, command: "false"}
      ]

      output = Overmind.format_ps(missions)
      assert output =~ "restarting"
      assert output =~ "3"
    end

    test "formats uptime in minutes" do
      missions = [%{id: "a1b2c3d4", name: "calm-beam", type: :task, status: :running, restart_count: 0, parent: nil, children: 0, uptime: 120, command: "x"}]
      assert Overmind.format_ps(missions) =~ "2m"
    end

    test "formats uptime in hours" do
      missions = [%{id: "a1b2c3d4", name: "dark-core", type: :task, status: :stopped, restart_count: 0, parent: nil, children: 0, uptime: 7200, command: "x"}]
      assert Overmind.format_ps(missions) =~ "2h"
    end
  end

  describe "format_ps_tree/1" do
    test "shows root missions and children with tree chars" do
      missions = [
        %{id: "parent01", name: "root", type: :task, status: :running, restart_count: 0, parent: nil, children: 1, uptime: 10, command: "sleep 60"},
        %{id: "child001", name: "kid", type: :task, status: :running, restart_count: 0, parent: "parent01", children: 0, uptime: 5, command: "echo hi"}
      ]

      output = Overmind.format_ps_tree(missions)
      assert output =~ "parent01"
      assert output =~ "child001"
    end

    test "orphans appear at root level" do
      missions = [
        %{id: "orphan01", name: "lonely", type: :task, status: :running, restart_count: 0, parent: "dead1234", children: 0, uptime: 10, command: "sleep 60"}
      ]

      output = Overmind.format_ps_tree(missions)
      assert output =~ "orphan01"
    end
  end
end
