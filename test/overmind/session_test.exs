defmodule Overmind.SessionTest do
  use ExUnit.Case

  alias Overmind.Session

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

  describe "generate_id/0" do
    test "returns 8-char lowercase hex string" do
      id = Session.generate_id()
      assert String.length(id) == 8
      assert Regex.match?(~r/^[0-9a-f]{8}$/, id)
    end

    test "unique across 100 calls" do
      ids = for _ <- 1..100, do: Session.generate_id()
      assert length(Enum.uniq(ids)) == 100
    end
  end

  describe "start_link/1" do
    test "starts process and registers in ETS with :running status" do
      id = Session.generate_id()
      {:ok, pid} = Session.start_link(id: id, command: "sleep 60")

      assert is_pid(pid)
      assert Process.alive?(pid)

      [{^id, ^pid, "sleep 60", :running, started_at}] =
        :ets.lookup(:overmind_sessions, id)

      assert is_integer(started_at)
    end

    test "get_info/1 returns metadata with os_pid" do
      id = Session.generate_id()
      {:ok, _pid} = Session.start_link(id: id, command: "sleep 60")

      {:ok, info} = Session.get_info(id)
      assert info.id == id
      assert info.command == "sleep 60"
      assert info.status == :running
      assert is_integer(info.os_pid)
      assert info.os_pid > 0
    end
  end

  describe "get_logs/1" do
    test "returns stdout from echo command" do
      id = Session.generate_id()
      {:ok, _pid} = Session.start_link(id: id, command: "echo hello")
      Process.sleep(100)

      {:ok, logs} = Session.get_logs(id)
      assert logs =~ "hello"
    end

    test "captures stderr" do
      id = Session.generate_id()
      {:ok, _pid} = Session.start_link(id: id, command: "sh -c 'echo error >&2'")
      Process.sleep(100)

      {:ok, logs} = Session.get_logs(id)
      assert logs =~ "error"
    end

    test "empty string when no output" do
      id = Session.generate_id()
      {:ok, _pid} = Session.start_link(id: id, command: "sleep 60")
      Process.sleep(50)

      {:ok, logs} = Session.get_logs(id)
      assert logs == ""
    end
  end

  describe "exit detection" do
    test "exit 0 sets :stopped status in ETS" do
      id = Session.generate_id()
      {:ok, pid} = Session.start_link(id: id, command: "true")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      [{^id, _, _, :stopped, _}] = :ets.lookup(:overmind_sessions, id)
    end

    test "non-zero exit sets :crashed status in ETS" do
      id = Session.generate_id()
      {:ok, pid} = Session.start_link(id: id, command: "false")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      [{^id, _, _, :crashed, _}] = :ets.lookup(:overmind_sessions, id)
    end

    test "logs persisted to ETS after exit" do
      id = Session.generate_id()
      {:ok, pid} = Session.start_link(id: id, command: "echo goodbye")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      [{{:logs, ^id}, logs}] = :ets.lookup(:overmind_sessions, {:logs, id})
      assert logs =~ "goodbye"
    end
  end
end
