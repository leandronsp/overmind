defmodule Overmind.CLITest do
  use ExUnit.Case

  import ExUnit.CaptureIO

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

  test "no args prints usage" do
    output = capture_io(fn -> Overmind.CLI.main([]) end)
    assert output =~ "Usage:"
    assert output =~ "overmind"
  end

  test "unknown command prints error and usage" do
    output = capture_io(fn -> Overmind.CLI.main(["wat"]) end)
    assert output =~ "Unknown command"
    assert output =~ "Usage:"
  end

  test "run command starts session and prints ID" do
    output = capture_io(fn -> Overmind.CLI.main(["run", "--agent", "sleep 60"]) end)
    assert output =~ "Started session"
  end

  test "run without --agent prints error" do
    output = capture_io(fn -> Overmind.CLI.main(["run"]) end)
    assert output =~ "Missing --agent"
  end

  test "ps command lists sessions" do
    {:ok, _id} = Overmind.run("sleep 60")
    Process.sleep(50)

    output = capture_io(fn -> Overmind.CLI.main(["ps"]) end)
    assert output =~ "sleep 60"
    assert output =~ "running"
  end

  test "ps with no sessions prints header only" do
    output = capture_io(fn -> Overmind.CLI.main(["ps"]) end)
    assert output =~ "ID"
    assert output =~ "COMMAND"
  end

  test "logs command prints session logs" do
    {:ok, id} = Overmind.run("echo cli-test")
    Process.sleep(200)

    output = capture_io(fn -> Overmind.CLI.main(["logs", id]) end)
    assert output =~ "cli-test"
  end

  test "logs with unknown ID prints error" do
    output = capture_io(fn -> Overmind.CLI.main(["logs", "bad12345"]) end)
    assert output =~ "not found"
  end

  test "stop command stops session" do
    {:ok, id} = Overmind.run("sleep 60")
    Process.sleep(50)

    output = capture_io(fn -> Overmind.CLI.main(["stop", id]) end)
    assert output =~ "Stopped"
  end

  test "kill command kills session" do
    {:ok, id} = Overmind.run("sleep 60")
    Process.sleep(50)

    output = capture_io(fn -> Overmind.CLI.main(["kill", id]) end)
    assert output =~ "Killed"
  end
end
