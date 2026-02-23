defmodule Overmind.MissionTest do
  use ExUnit.Case

  alias Overmind.Mission

  setup do
    Overmind.Test.MissionHelper.cleanup_missions()
    :ok
  end

  describe "generate_id/0" do
    test "returns 8-char lowercase hex string" do
      id = Mission.generate_id()
      assert String.length(id) == 8
      assert Regex.match?(~r/^[0-9a-f]{8}$/, id)
    end

    test "unique across 100 calls" do
      ids = for _ <- 1..100, do: Mission.generate_id()
      assert length(Enum.uniq(ids)) == 100
    end
  end

  describe "start_link/1" do
    test "starts process and registers in ETS with :running status" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "sleep 60")

      assert is_pid(pid)
      assert Process.alive?(pid)

      [{^id, ^pid, "sleep 60", :running, started_at}] =
        :ets.lookup(:overmind_missions, id)

      assert is_integer(started_at)
    end

    test "stores original command in ETS, not wrapped" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "hello", provider: Overmind.Provider.Claude)

      [{^id, _, "hello", :running, _}] = :ets.lookup(:overmind_missions, id)
    end

    test "get_info/1 returns metadata with os_pid" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60")

      {:ok, info} = Mission.get_info(id)
      assert info.id == id
      assert info.command == "sleep 60"
      assert info.status == :running
      assert is_integer(info.os_pid)
      assert info.os_pid > 0
    end
  end

  describe "command chains" do
    test "semicolon chain runs all commands" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "echo oi; sleep 1; echo tchau")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3000

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "oi"
      assert logs =~ "tchau"
    end

    test "&& chain runs all commands on success" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "echo first && sleep 1 && echo last")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3000

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "first"
      assert logs =~ "last"
    end

    test "&& chain stops on failure" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "echo before && false && echo after")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "before"
      refute logs =~ "after"
    end
  end

  describe "get_logs/1" do
    test "returns stdout from echo command" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "echo hello")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "hello"
    end

    test "captures stderr" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "sh -c 'echo error >&2'")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "error"
    end

    test "empty string when no output" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60")
      Process.sleep(50)

      {:ok, logs} = Mission.get_logs(id)
      assert logs == ""
    end
  end

  describe "stream-json parsing" do
    test "parses JSON lines and extracts text for logs" do
      script = ~s(sh -c 'echo "{\\\"type\\\":\\\"assistant\\\",\\\"message\\\":{\\\"content\\\":[{\\\"type\\\":\\\"text\\\",\\\"text\\\":\\\"Canberra\\\"}]}}"')

      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: script, provider: Overmind.Provider.TestClaude)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "Canberra"
    end

    test "stores raw events from JSON lines" do
      script = ~s(sh -c 'echo "{\\\"type\\\":\\\"result\\\",\\\"subtype\\\":\\\"success\\\",\\\"result\\\":\\\"Done\\\",\\\"duration_ms\\\":100,\\\"cost_usd\\\":0.01,\\\"is_error\\\":false}"')

      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: script, provider: Overmind.Provider.TestClaude)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      {:ok, events} = Mission.get_raw_events(id)
      assert length(events) == 1
      assert hd(events)["type"] == "result"
    end

    test "plain text with Raw provider" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "echo plaintext")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "plaintext"

      {:ok, events} = Mission.get_raw_events(id)
      assert events == []
    end
  end

  describe "exit detection" do
    test "exit 0 sets :stopped status in ETS" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "true")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      [{^id, _, _, :stopped, _}] = :ets.lookup(:overmind_missions, id)
    end

    test "non-zero exit sets :crashed status in ETS" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "false")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      [{^id, _, _, :crashed, _}] = :ets.lookup(:overmind_missions, id)
    end

    test "logs persisted to ETS after exit" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "echo goodbye")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      [{{:logs, ^id}, logs}] = :ets.lookup(:overmind_missions, {:logs, id})
      assert logs =~ "goodbye"
    end

    test "raw_events persisted to ETS after exit" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "echo done")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      [{{:raw_events, ^id}, events}] = :ets.lookup(:overmind_missions, {:raw_events, id})
      assert is_list(events)
    end
  end
end
