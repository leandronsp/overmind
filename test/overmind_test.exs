defmodule OvermindTest do
  use ExUnit.Case

  setup do
    cleanup_sessions()
    :ok
  end

  defp cleanup_sessions do
    :ets.match(:overmind_sessions, {:"$1", :_, :_, :running, :_})
    |> List.flatten()
    |> Enum.each(fn id ->
      case :ets.lookup(:overmind_sessions, id) do
        [{_, pid, _, :running, _}] ->
          try do
            GenServer.stop(pid, :normal, 100)
          catch
            :exit, _ -> :ok
          end

        _ ->
          :ok
      end
    end)

    :ets.delete_all_objects(:overmind_sessions)
    Process.sleep(10)
  end

  describe "run/1" do
    test "returns {:ok, id} and session is visible in ETS" do
      {:ok, id} = Overmind.run("sleep 60")

      assert String.length(id) == 8
      [{^id, pid, "sleep 60", :running, _}] = :ets.lookup(:overmind_sessions, id)
      assert is_pid(pid)
    end

    test "error for empty command" do
      assert {:error, :empty_command} = Overmind.run("")
    end
  end

  describe "ps/0" do
    test "empty list when no sessions" do
      assert Overmind.ps() == []
    end

    test "returns session info with uptime" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(10)

      [session] = Overmind.ps()
      assert session.id == id
      assert session.command == "sleep 60"
      assert session.status == :running
      assert is_integer(session.uptime)
      assert session.uptime >= 0
    end

    test "includes naturally exited sessions" do
      {:ok, id} = Overmind.run("true")
      Process.sleep(100)

      sessions = Overmind.ps()
      assert Enum.any?(sessions, fn s -> s.id == id and s.status == :stopped end)
    end
  end

  describe "logs/1" do
    test "returns logs from running session" do
      {:ok, id} = Overmind.run("sh -c 'echo running; sleep 60'")
      Process.sleep(100)

      {:ok, logs} = Overmind.logs(id)
      assert logs =~ "running"
    end

    test "returns logs from dead session" do
      {:ok, id} = Overmind.run("echo dead")
      Process.sleep(200)

      {:ok, logs} = Overmind.logs(id)
      assert logs =~ "dead"
    end

    test "error for unknown ID" do
      assert {:error, :not_found} = Overmind.logs("nonexist")
    end
  end

  describe "stop/1" do
    test "stops a running session and removes from ETS" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      assert :ok = Overmind.stop(id)
      Process.sleep(100)

      assert :ets.lookup(:overmind_sessions, id) == []
    end

    test "error for unknown session" do
      assert {:error, :not_found} = Overmind.stop("nonexist")
    end

    test "error for already stopped session" do
      {:ok, id} = Overmind.run("true")
      Process.sleep(200)

      assert {:error, :not_running} = Overmind.stop(id)
    end
  end

  describe "kill/1" do
    test "force-kills a running session and removes from ETS" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      assert :ok = Overmind.kill(id)
      Process.sleep(100)

      assert :ets.lookup(:overmind_sessions, id) == []
    end

    test "works on SIGTERM-resistant processes" do
      {:ok, id} = Overmind.run("sh -c 'trap \"\" TERM; sleep 60'")
      Process.sleep(50)

      assert :ok = Overmind.kill(id)
      Process.sleep(100)

      assert :ets.lookup(:overmind_sessions, id) == []
    end

    test "error for unknown session" do
      assert {:error, :not_found} = Overmind.kill("nonexist")
    end

    test "error for already stopped session" do
      {:ok, id} = Overmind.run("true")
      Process.sleep(200)

      assert {:error, :not_running} = Overmind.kill(id)
    end
  end
end
