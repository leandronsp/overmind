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
      Process.sleep(100)

      [{^id, _, "echo hello", _, _}] = :ets.lookup(:overmind_missions, id)
    end

    test "error for empty command with provider" do
      assert {:error, :empty_command} = Overmind.run("", Overmind.Provider.Claude)
    end
  end

  describe "ps/0" do
    test "empty list when no missions" do
      assert Overmind.ps() == []
    end

    test "returns mission info with uptime" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(10)

      [mission] = Overmind.ps()
      assert mission.id == id
      assert mission.command == "sleep 60"
      assert mission.status == :running
      assert is_integer(mission.uptime)
      assert mission.uptime >= 0
    end

    test "includes naturally exited missions" do
      {:ok, id} = Overmind.run("true")
      Process.sleep(100)

      missions = Overmind.ps()
      assert Enum.any?(missions, fn m -> m.id == id and m.status == :stopped end)
    end

    test "does not include raw_events tuples" do
      {:ok, id} = Overmind.run("echo test")
      Process.sleep(200)

      missions = Overmind.ps()
      assert Enum.all?(missions, fn m -> is_binary(m.id) end)
      assert Enum.any?(missions, fn m -> m.id == id end)
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
      Process.sleep(200)

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
      Process.sleep(200)

      {:ok, events} = Overmind.raw_events(id)
      assert events == []
    end

    test "error for unknown ID" do
      assert {:error, :not_found} = Overmind.raw_events("nonexist")
    end
  end

  describe "stop/1" do
    test "stops a running mission, mission stays in ETS as :stopped" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      assert :ok = Overmind.stop(id)
      Process.sleep(200)

      [{^id, _, _, :stopped, _}] = :ets.lookup(:overmind_missions, id)
    end

    test "error for unknown mission" do
      assert {:error, :not_found} = Overmind.stop("nonexist")
    end

    test "error for already stopped mission" do
      {:ok, id} = Overmind.run("true")
      Process.sleep(200)

      assert {:error, :not_running} = Overmind.stop(id)
    end
  end

  describe "kill/1" do
    test "force-kills a running mission and removes from ETS" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      assert :ok = Overmind.kill(id)
      Process.sleep(100)

      assert :ets.lookup(:overmind_missions, id) == []
    end

    test "works on SIGTERM-resistant processes" do
      {:ok, id} = Overmind.run("sh -c 'trap \"\" TERM; sleep 60'")
      Process.sleep(50)

      assert :ok = Overmind.kill(id)
      Process.sleep(100)

      assert :ets.lookup(:overmind_missions, id) == []
    end

    test "kills a stopped mission and removes from ETS" do
      {:ok, id} = Overmind.run("true")
      Process.sleep(200)

      assert :ok = Overmind.kill(id)
      assert :ets.lookup(:overmind_missions, id) == []
    end

    test "error for unknown mission" do
      assert {:error, :not_found} = Overmind.kill("nonexist")
    end
  end
end
