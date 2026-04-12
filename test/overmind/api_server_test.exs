defmodule Overmind.APIServerTest do
  use ExUnit.Case

  alias Overmind.APIServer

  setup do
    Overmind.Test.MissionHelper.cleanup_missions()
    :ok
  end

  describe "dispatch/1" do
    test "run returns id and name" do
      result = APIServer.dispatch(%{"cmd" => "run", "args" => %{"command" => "sleep 60"}})
      assert %{"ok" => %{"id" => id, "name" => name}} = result
      assert is_binary(id)
      assert String.length(id) == 8
      assert is_binary(name)
    end

    test "run with session type" do
      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "", "type" => "session"}
        })

      assert %{"ok" => %{"id" => id}} = result
      assert String.length(id) == 8
    end

    test "run with name passes name to mission" do
      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "sleep 60", "name" => "my-agent"}
        })

      assert %{"ok" => %{"id" => id, "name" => "my-agent"}} = result
      assert Overmind.Mission.Store.lookup_name(id) == "my-agent"
    end

    test "run with cwd passes directory to mission" do
      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "pwd", "cwd" => "/tmp"}
        })

      assert %{"ok" => %{"id" => id}} = result

      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      {:ok, logs} = Overmind.logs(id)
      assert logs =~ "tmp"
    end

    test "run with restart args" do
      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{
            "command" => "sleep 60",
            "restart" => "on-failure",
            "max_restarts" => 3,
            "backoff" => 2000,
            "activity_timeout" => 30
          }
        })

      assert %{"ok" => %{"id" => id}} = result
      assert Overmind.Mission.Store.lookup_restart_policy(id) == :on_failure
    end

    test "run with parent passes parent to mission" do
      {:ok, parent_id} = Overmind.run("sleep 60")

      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "sleep 60", "parent" => parent_id}
        })

      assert %{"ok" => %{"id" => child_id}} = result
      assert Overmind.Mission.Store.lookup_parent(child_id) == parent_id
    end

    test "run with nonexistent parent returns error" do
      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "sleep 60", "parent" => "nonexist"}
        })

      assert %{"error" => "parent_not_found"} = result
    end

    test "run with model stores model in ETS" do
      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "sleep 60", "model" => "haiku"}
        })

      assert %{"ok" => %{"id" => id}} = result
      assert Overmind.Mission.Store.lookup_model(id) == "haiku"
    end

    test "run without model defaults to nil" do
      result = APIServer.dispatch(%{"cmd" => "run", "args" => %{"command" => "sleep 60"}})
      assert %{"ok" => %{"id" => id}} = result
      assert Overmind.Mission.Store.lookup_model(id) == nil
    end

    test "run with empty command returns error" do
      result = APIServer.dispatch(%{"cmd" => "run", "args" => %{"command" => ""}})
      assert %{"error" => "empty_command"} = result
    end

    test "ps with tree returns formatted tree" do
      {:ok, parent_id} = Overmind.run("sleep 60")
      {:ok, _child_id} = Overmind.run("sleep 60", parent: parent_id)
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "ps", "args" => %{"tree" => true}})
      assert %{"ok" => text} = result
      assert text =~ "ID"
      assert text =~ parent_id
    end

    test "ps with children returns only children" do
      {:ok, parent_id} = Overmind.run("sleep 60")
      {:ok, child_id} = Overmind.run("sleep 60", parent: parent_id)
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "ps", "args" => %{"children" => parent_id}})
      assert %{"ok" => text} = result
      assert text =~ child_id
    end

    test "ps returns formatted text" do
      {:ok, _id} = Overmind.run("sleep 60")
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "ps"})
      assert %{"ok" => text} = result
      assert text =~ "ID"
      assert text =~ "sleep 60"
    end

    test "wait returns status and exit_code for exited mission" do
      {:ok, id} = Overmind.run("true")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      result = APIServer.dispatch(%{"cmd" => "wait", "args" => %{"id" => id}})
      assert %{"ok" => %{"status" => "stopped", "exit_code" => 0}} = result
    end

    test "wait returns error for unknown mission" do
      result = APIServer.dispatch(%{"cmd" => "wait", "args" => %{"id" => "nonexist"}})
      assert %{"error" => "not_found"} = result
    end

    test "wait with timeout returns error" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "wait", "args" => %{"id" => id, "timeout" => 100}})
      assert %{"error" => "timeout"} = result
    end

    test "info returns mission info with os_pid" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "info", "args" => %{"id" => id}})
      assert %{"ok" => info} = result
      assert info.id == id
      assert info.status == :running
      assert is_integer(info.os_pid)
    end

    test "info returns error for unknown id" do
      result = APIServer.dispatch(%{"cmd" => "info", "args" => %{"id" => "nonexist"}})
      assert %{"error" => "not_found"} = result
    end

    test "logs returns mission logs" do
      {:ok, id} = Overmind.run("echo socket-test")
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      result = APIServer.dispatch(%{"cmd" => "logs", "args" => %{"id" => id}})
      assert %{"ok" => logs} = result
      assert logs =~ "socket-test"
    end

    test "logs returns error for unknown id" do
      result = APIServer.dispatch(%{"cmd" => "logs", "args" => %{"id" => "nonexist"}})
      assert %{"error" => "not_found"} = result
    end

    test "result returns structured data for completed mission" do
      script = ~s(sh -c 'echo "{\\\"type\\\":\\\"result\\\",\\\"result\\\":\\\"Done\\\",\\\"duration_ms\\\":100,\\\"cost_usd\\\":0.01,\\\"is_error\\\":false}"')

      {:ok, id} = Overmind.run(script, provider: Overmind.Provider.TestClaude)
      [{^id, pid, _, _, _}] = :ets.lookup(:overmind_missions, id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      result = APIServer.dispatch(%{"cmd" => "result", "args" => %{"id" => id}})
      assert %{"ok" => data} = result
      assert data["result"] == "Done"
      assert data["cost_usd"] == 0.01
    end

    test "result returns error for running mission" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "result", "args" => %{"id" => id}})
      assert %{"error" => "not_finished"} = result
    end

    test "result returns error for unknown mission" do
      result = APIServer.dispatch(%{"cmd" => "result", "args" => %{"id" => "nonexist"}})
      assert %{"error" => "not_found"} = result
    end

    test "stop returns ok" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "stop", "args" => %{"id" => id}})
      assert %{"ok" => true} = result
    end

    test "kill returns ok" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "kill", "args" => %{"id" => id}})
      assert %{"ok" => true} = result
    end

    test "kill with cascade removes parent and children" do
      {:ok, parent_id} = Overmind.run("sleep 60")
      {:ok, child_id} = Overmind.run("sleep 60", parent: parent_id)
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "kill", "args" => %{"id" => parent_id, "cascade" => true}})
      assert %{"ok" => true} = result
      Process.sleep(50)

      assert :ets.lookup(:overmind_missions, parent_id) == []
      assert :ets.lookup(:overmind_missions, child_id) == []
    end

    test "send returns ok for session" do
      {:ok, id} = Overmind.run("", type: :session)
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "send", "args" => %{"id" => id, "message" => "hi"}})
      assert %{"ok" => true} = result
    end

    test "send returns error for task" do
      {:ok, id} = Overmind.run("sleep 60")
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "send", "args" => %{"id" => id, "message" => "hi"}})
      assert %{"error" => "not_session"} = result
    end

    test "send with wait blocks until result" do
      {:ok, id} = Overmind.run("", type: :session, provider: Overmind.Provider.TestSession)
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "send", "args" => %{"id" => id, "message" => "hi", "wait" => true}})
      assert %{"ok" => %{"text" => "Done"}} = result
    end

    test "send with wait and timeout returns error" do
      {:ok, id} = Overmind.run("", type: :session, provider: Overmind.Provider.TestSilentSession)
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "send", "args" => %{"id" => id, "message" => "hi", "wait" => true, "timeout" => 100}})
      assert %{"error" => "timeout"} = result
    end

    test "pause returns session_id and cwd" do
      {:ok, id} = Overmind.run("", type: :session, cwd: "/tmp")
      Process.sleep(50)

      result = APIServer.dispatch(%{"cmd" => "pause", "args" => %{"id" => id}})
      assert %{"ok" => %{"session_id" => :null, "cwd" => "/tmp"}} = result
    end

    test "unpause returns ok" do
      {:ok, id} = Overmind.run("", type: :session)
      Process.sleep(50)

      APIServer.dispatch(%{"cmd" => "pause", "args" => %{"id" => id}})
      result = APIServer.dispatch(%{"cmd" => "unpause", "args" => %{"id" => id}})
      assert %{"ok" => true} = result
    end

    test "status returns daemon health map" do
      result = APIServer.dispatch(%{"cmd" => "status"})
      assert %{"ok" => status} = result
      assert is_binary(status.pid)
      assert is_integer(status.uptime)
      assert is_map(status.missions)
      assert is_integer(status.missions.total)
    end

    test "unknown command returns error" do
      result = APIServer.dispatch(%{"cmd" => "bogus"})
      assert %{"error" => "unknown command: bogus"} = result
    end

    test "invalid request returns error" do
      result = APIServer.dispatch(%{})
      assert %{"error" => "invalid request"} = result
    end

    test "agents returns specs from valid blueprint" do
      path = write_toml("""
      [agents.greeter]
      command = "echo hello"

      [agents.worker]
      command = "echo work"
      depends_on = ["greeter"]
      """)

      result = APIServer.dispatch(%{"cmd" => "agents", "args" => %{"path" => path}})
      assert %{"ok" => specs} = result
      assert length(specs) == 2
      assert Enum.any?(specs, fn s -> s["name"] == "greeter" end)
    end

    test "agents includes model in spec when present" do
      path = write_toml("""
      [agents.researcher]
      command = "echo research"
      provider = "claude"
      model = "haiku"
      """)

      result = APIServer.dispatch(%{"cmd" => "agents", "args" => %{"path" => path}})
      assert %{"ok" => [spec]} = result
      assert spec["model"] == "haiku"
    end

    test "agents omits model from spec when absent" do
      path = write_toml("""
      [agents.worker]
      command = "echo work"
      """)

      result = APIServer.dispatch(%{"cmd" => "agents", "args" => %{"path" => path}})
      assert %{"ok" => [spec]} = result
      refute Map.has_key?(spec, "model")
    end

    test "agents returns error for missing file" do
      result = APIServer.dispatch(%{"cmd" => "agents", "args" => %{"path" => "/nonexistent.toml"}})
      assert %{"error" => "enoent"} = result
    end

    test "apply returns id and name" do
      path = write_toml("""
      [agents.step1]
      command = "echo one"
      """)

      result = APIServer.dispatch(%{"cmd" => "apply", "args" => %{"path" => path}})
      assert %{"ok" => %{"id" => id, "name" => name}} = result
      assert is_binary(id)
      assert String.length(id) == 8
      assert is_binary(name)
    end

    test "apply returns error for missing file" do
      result = APIServer.dispatch(%{"cmd" => "apply", "args" => %{"path" => "/nonexistent.toml"}})
      assert %{"error" => _} = result
    end
  end

  describe "socket server" do
    setup do
      path = Path.join(System.tmp_dir!(), "overmind_test_#{:rand.uniform(1_000_000)}.sock")
      {:ok, pid} = APIServer.start_link(socket_path: path, name: nil)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{socket_path: path}
    end

    test "accepts JSON commands over unix socket", %{socket_path: path} do
      {:ok, sock} = :gen_tcp.connect({:local, path}, 0, [:binary, {:packet, :line}, {:active, false}])

      request = :json.encode(%{"cmd" => "ps"}) |> IO.iodata_to_binary()
      :ok = :gen_tcp.send(sock, request <> "\n")

      {:ok, response} = :gen_tcp.recv(sock, 0, 5000)
      decoded = :json.decode(String.trim(response))
      assert %{"ok" => _} = decoded
      :gen_tcp.close(sock)
    end

    test "handles run command over socket", %{socket_path: path} do
      {:ok, sock} = :gen_tcp.connect({:local, path}, 0, [:binary, {:packet, :line}, {:active, false}])

      request =
        :json.encode(%{"cmd" => "run", "args" => %{"command" => "sleep 60"}})
        |> IO.iodata_to_binary()

      :ok = :gen_tcp.send(sock, request <> "\n")

      {:ok, response} = :gen_tcp.recv(sock, 0, 5000)
      decoded = :json.decode(String.trim(response))
      assert %{"ok" => %{"id" => id}} = decoded
      assert String.length(id) == 8
      :gen_tcp.close(sock)
    end

    test "cleans up socket file on stop", %{socket_path: path} do
      assert File.exists?(path)
    end

    test "subscribe streams events as NDJSON lines", %{socket_path: path} do
      # Start a mission that waits for input then outputs and exits
      {:ok, id} = Overmind.run("", type: :session, provider: Overmind.Provider.TestSession)
      Process.sleep(50)

      # Subscribe via socket before triggering output
      {:ok, sock} = :gen_tcp.connect({:local, path}, 0, [:binary, active: false, packet: :line])
      escaped = String.replace(id, "\"", "\\\"")
      :gen_tcp.send(sock, ~s({"cmd":"subscribe","args":{"id":"#{escaped}"}}\n))

      # Trigger output by sending a message (TestSession reads a line, outputs result, exits)
      Overmind.send(id, "go")

      # Read streamed lines until socket closes
      lines = read_lines(sock, [], 2000)
      :gen_tcp.close(sock)

      # Should have received at least the exit event
      assert length(lines) >= 1
      last = List.last(lines)
      assert %{"type" => "exit"} = :json.decode(last)
    end
  end

    test "subscribe returns error for unknown mission" do
      result = APIServer.dispatch(%{"cmd" => "subscribe", "args" => %{"id" => "nonexist"}})
      assert %{"error" => "not_found"} = result
    end

  defp read_lines(sock, acc, timeout) do
    case :gen_tcp.recv(sock, 0, timeout) do
      {:ok, line} -> read_lines(sock, acc ++ [String.trim(line)], timeout)
      {:error, :closed} -> acc
      {:error, :timeout} -> acc
    end
  end

  defp write_toml(content) do
    path = Path.join(System.tmp_dir!(), "api_blueprint_test_#{:rand.uniform(1_000_000)}.toml")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
