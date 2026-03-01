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

    test "stores type in ETS, defaults to :task" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60")
      assert Overmind.Mission.Store.lookup_type(id) == :task
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

  describe "session mode" do
    test "session mission stays alive (stdin open)" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "", type: :session)
      Process.sleep(100)

      assert Process.alive?(pid)
      assert {:running, ^pid, _, _} = Overmind.Mission.Store.lookup(id)
    end

    test "session with initial prompt sends it via stdin" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "hello", type: :session)
      Process.sleep(100)

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "hello"
    end

    test "session with empty command sends nothing" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "", type: :session)
      Process.sleep(100)

      {:ok, logs} = Mission.get_logs(id)
      assert logs == ""
      assert Process.alive?(pid)
    end

    test "task mission with cat exits immediately (stdin closed)" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "cat")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end
  end

  describe "name" do
    test "auto-generates name when not provided" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60")

      name = Overmind.Mission.Store.lookup_name(id)
      assert name != nil
      assert Regex.match?(~r/^[a-z]+-[a-z]+$/, name)
    end

    test "uses provided name" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60", name: "my-agent")

      assert Overmind.Mission.Store.lookup_name(id) == "my-agent"
    end
  end

  describe "cwd" do
    test "pwd with cwd /tmp shows tmp in logs" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "pwd", cwd: "/tmp")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "tmp"
    end

    test "stores cwd in ETS when provided" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60", cwd: "/tmp")

      assert Overmind.Mission.Store.lookup_cwd(id) == "/tmp"
    end

    test "does not store cwd when nil" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60")

      assert Overmind.Mission.Store.lookup_cwd(id) == nil
    end
  end

  describe "session_id capture" do
    test "captures session_id from system init event" do
      script = ~s(sh -c 'echo "{\\"type\\":\\"system\\",\\"subtype\\":\\"init\\",\\"session_id\\":\\"sess-xyz\\"}"; sleep 60')

      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: script, provider: Overmind.Provider.TestClaude)
      Process.sleep(200)

      assert Overmind.Mission.Store.lookup_session_id(id) == "sess-xyz"
    end
  end

  describe "send_message/2" do
    test "sends message to session and appears in logs" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "", type: :session)
      Process.sleep(50)

      assert :ok = Mission.send_message(id, "ping")
      Process.sleep(100)

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "[human] ping"
      assert logs =~ "ping\n"
    end

    test "error for not_found" do
      assert {:error, :not_found} = Mission.send_message("nonexist", "hello")
    end

    test "error for not_running (exited mission)" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "true")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      assert {:error, :not_running} = Mission.send_message(id, "hello")
    end

    test "error for task mission" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60", type: :task)
      Process.sleep(50)

      assert {:error, :not_session} = Mission.send_message(id, "hello")
    end
  end

  describe "pause/unpause" do
    test "pause returns session_id and blocks send" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "", type: :session)
      Process.sleep(50)

      assert {:ok, nil} = Mission.pause(id)
      assert {:error, :paused} = Mission.send_message(id, "nope")
    end

    test "unpause re-enables send" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "", type: :session)
      Process.sleep(50)

      assert {:ok, nil} = Mission.pause(id)
      assert :ok = Mission.unpause(id)
      assert :ok = Mission.send_message(id, "hello")
    end

    test "pause on task mission errors" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60", type: :task)
      Process.sleep(50)

      assert {:error, :not_session} = Mission.pause(id)
    end

    test "pause on not found errors" do
      assert {:error, :not_found} = Mission.pause("nonexist")
    end

    test "attached flag in store" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "", type: :session)
      Process.sleep(50)

      {:ok, _} = Mission.pause(id)
      assert Overmind.Mission.Store.lookup_attached(id) == true

      :ok = Mission.unpause(id)
      assert Overmind.Mission.Store.lookup_attached(id) == false
    end
  end

  describe "restart opts" do
    test "stores restart_policy in ETS" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60", restart_policy: :on_failure)

      assert Overmind.Mission.Store.lookup_restart_policy(id) == :on_failure
    end

    test "defaults restart_policy to :never" do
      id = Mission.generate_id()
      {:ok, _pid} = Mission.start_link(id: id, command: "sleep 60")

      assert Overmind.Mission.Store.lookup_restart_policy(id) == :never
    end

    test ":never policy — crash still stops GenServer" do
      id = Mission.generate_id()
      {:ok, pid} = Mission.start_link(id: id, command: "false", restart_policy: :never)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      [{^id, _, _, :crashed, _}] = :ets.lookup(:overmind_missions, id)
    end
  end

  describe "restart: :on_failure" do
    test "restarts on non-zero exit" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "sh -c 'echo attempt; exit 1'",
          restart_policy: :on_failure,
          max_restarts: 1,
          backoff_ms: 50
        )

      # Wait for first exit + restart + second exit + GenServer stops (max reached)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3000

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "--- restart #1"
      # Logs persist across restarts — "attempt" appears at least twice
      assert length(String.split(logs, "attempt")) >= 3
    end

    test "does NOT restart on exit 0" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "true",
          restart_policy: :on_failure,
          max_restarts: 3,
          backoff_ms: 50
        )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      [{^id, _, _, :stopped, _}] = :ets.lookup(:overmind_missions, id)
      assert Overmind.Mission.Store.lookup_restart_count(id) == 0
    end
  end

  describe "restart: :always" do
    test "restarts even on exit 0" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "true",
          restart_policy: :always,
          max_restarts: 1,
          backoff_ms: 50
        )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3000

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "--- restart #1"
    end
  end

  describe "restart: explicit stop prevents restart" do
    test "stop during running prevents restart" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "sleep 60",
          restart_policy: :always,
          max_restarts: 3,
          backoff_ms: 50
        )

      Process.sleep(50)
      ref = Process.monitor(pid)
      :ok = Mission.stop(id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      [{^id, _, _, :stopped, _}] = :ets.lookup(:overmind_missions, id)
    end
  end

  describe "restart: max_restarts cap" do
    test "stops after reaching max_restarts" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "false",
          restart_policy: :on_failure,
          max_restarts: 2,
          backoff_ms: 50
        )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

      [{^id, _, _, :crashed, _}] = :ets.lookup(:overmind_missions, id)
      assert Overmind.Mission.Store.lookup_restart_count(id) == 2
    end

    test "max_restarts 0 means unlimited" do
      # Use a command that exits after 3 runs via a temp file counter
      tmpfile = Path.join(System.tmp_dir!(), "overmind_test_#{:rand.uniform(1_000_000)}")
      File.write!(tmpfile, "0")

      cmd = "sh -c 'n=$(cat #{tmpfile}); n=$((n+1)); echo $n > #{tmpfile}; if [ $n -ge 4 ]; then exit 0; else exit 1; fi'"

      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: cmd,
          restart_policy: :on_failure,
          max_restarts: 0,
          backoff_ms: 50
        )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

      # Eventually exits cleanly (exit 0 on 4th run)
      [{^id, _, _, :stopped, _}] = :ets.lookup(:overmind_missions, id)
      # Restarted 3 times (runs 1-3 failed, run 4 succeeded)
      assert Overmind.Mission.Store.lookup_restart_count(id) == 3

      File.rm(tmpfile)
    end
  end

  describe "restart: exponential backoff" do
    test "restart delay increases exponentially" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "false",
          restart_policy: :on_failure,
          max_restarts: 2,
          backoff_ms: 100
        )

      # First restart at ~100ms, second at ~200ms
      # Total time should be > 250ms (not just 200ms = 2 * 100ms flat)
      t0 = System.monotonic_time(:millisecond)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
      elapsed = System.monotonic_time(:millisecond) - t0

      # With exponential: 100 + 200 = 300ms minimum
      assert elapsed >= 250
    end
  end

  describe "restart: log markers" do
    test "restart marker includes count and timestamp" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "false",
          restart_policy: :on_failure,
          max_restarts: 1,
          backoff_ms: 50
        )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3000

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ ~r/--- restart #1 at \d{4}-\d{2}-\d{2}/
    end
  end

  describe "stop during :restarting" do
    test "cancels pending restart and stops GenServer" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "false",
          restart_policy: :on_failure,
          max_restarts: 5,
          backoff_ms: 5000
        )

      # Wait for the process to enter :restarting
      Process.sleep(200)
      assert {:restarting, ^pid, _, _} = Overmind.Mission.Store.lookup(id)

      ref = Process.monitor(pid)
      assert :ok = Mission.stop(id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      [{^id, _, _, :stopped, _}] = :ets.lookup(:overmind_missions, id)
    end
  end

  describe "kill during :restarting" do
    test "cancels pending restart and cleans up" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "false",
          restart_policy: :on_failure,
          max_restarts: 5,
          backoff_ms: 5000
        )

      # Wait for the process to enter :restarting
      Process.sleep(200)
      assert {:restarting, ^pid, _, _} = Overmind.Mission.Store.lookup(id)

      ref = Process.monitor(pid)
      assert :ok = Mission.kill(id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      assert :ets.lookup(:overmind_missions, id) == []
    end
  end

  describe "activity tracking" do
    test "updates last_activity_at on port data" do
      id = Mission.generate_id()

      {:ok, _pid} =
        Mission.start_link(
          id: id,
          command: "sh -c 'echo hello; sleep 60'",
          activity_timeout: 60
        )

      Process.sleep(200)
      assert Overmind.Mission.Store.lookup_last_activity(id) != nil
    end
  end

  describe "stall detection" do
    test "kills process after no activity" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "sleep 60",
          activity_timeout: 1
        )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3000

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "killed: no activity for"
    end

    test "stall kill follows restart policy" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "sleep 60",
          activity_timeout: 1,
          restart_policy: :on_failure,
          max_restarts: 1,
          backoff_ms: 50
        )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

      {:ok, logs} = Mission.get_logs(id)
      assert logs =~ "killed: no activity for"
      assert logs =~ "--- restart #1"
    end

    test "continuous output prevents stall kill" do
      id = Mission.generate_id()

      {:ok, pid} =
        Mission.start_link(
          id: id,
          command: "sh -c 'while true; do echo tick; sleep 0.3; done'",
          activity_timeout: 1
        )

      # After 1.5s the process should still be alive (output resets timer)
      Process.sleep(1500)
      assert Process.alive?(pid)

      # Cleanup
      Mission.stop(id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
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
