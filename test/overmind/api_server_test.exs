defmodule Overmind.APIServerTest do
  use ExUnit.Case

  alias Overmind.APIServer

  setup do
    Overmind.Test.MissionHelper.cleanup_missions()
    :ok
  end

  describe "dispatch/1" do
    test "run returns mission id" do
      result = APIServer.dispatch(%{"cmd" => "run", "args" => %{"command" => "sleep 60"}})
      assert %{"ok" => id} = result
      assert is_binary(id)
      assert String.length(id) == 8
    end

    test "run with session type" do
      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "", "type" => "session"}
        })

      assert %{"ok" => id} = result
      assert String.length(id) == 8
    end

    test "run with name passes name to mission" do
      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "sleep 60", "name" => "my-agent"}
        })

      assert %{"ok" => id} = result
      assert Overmind.Mission.Store.lookup_name(id) == "my-agent"
    end

    test "run with cwd passes directory to mission" do
      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "pwd", "cwd" => "/tmp"}
        })

      assert %{"ok" => id} = result

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

      assert %{"ok" => id} = result
      assert Overmind.Mission.Store.lookup_restart_policy(id) == :on_failure
    end

    test "run with parent passes parent to mission" do
      {:ok, parent_id} = Overmind.run("sleep 60")

      result =
        APIServer.dispatch(%{
          "cmd" => "run",
          "args" => %{"command" => "sleep 60", "parent" => parent_id}
        })

      assert %{"ok" => child_id} = result
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

    test "unknown command returns error" do
      result = APIServer.dispatch(%{"cmd" => "bogus"})
      assert %{"error" => "unknown command: bogus"} = result
    end

    test "invalid request returns error" do
      result = APIServer.dispatch(%{})
      assert %{"error" => "invalid request"} = result
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
      assert %{"ok" => id} = decoded
      assert String.length(id) == 8
      :gen_tcp.close(sock)
    end

    test "cleans up socket file on stop", %{socket_path: path} do
      assert File.exists?(path)
    end
  end
end
