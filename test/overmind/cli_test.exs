defmodule Overmind.CLITest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  setup do
    Overmind.Test.MissionHelper.cleanup_missions()
    :ok
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

  test "run command starts mission with positional arg" do
    output = capture_io(fn -> Overmind.CLI.main(["run", "sleep", "60"]) end)
    assert output =~ "Started mission"
  end

  test "run without command prints error" do
    output = capture_io(fn -> Overmind.CLI.main(["run"]) end)
    assert output =~ "Missing command"
  end

  test "claude run without prompt prints error" do
    output = capture_io(fn -> Overmind.CLI.main(["claude", "run"]) end)
    assert output =~ "Missing prompt"
  end

  test "usage shows claude run" do
    output = capture_io(fn -> Overmind.CLI.main([]) end)
    assert output =~ "claude run"
  end

  test "ps command lists missions" do
    {:ok, _id} = Overmind.run("sleep 60")
    Process.sleep(50)

    output = capture_io(fn -> Overmind.CLI.main(["ps"]) end)
    assert output =~ "sleep 60"
    assert output =~ "running"
  end

  test "ps with no missions prints header only" do
    output = capture_io(fn -> Overmind.CLI.main(["ps"]) end)
    assert output =~ "ID"
    assert output =~ "COMMAND"
  end

  test "logs command prints mission logs" do
    {:ok, id} = Overmind.run("echo cli-test")
    Process.sleep(200)

    output = capture_io(fn -> Overmind.CLI.main(["logs", id]) end)
    assert output =~ "cli-test"
  end

  test "logs with unknown ID prints error" do
    output = capture_io(fn -> Overmind.CLI.main(["logs", "bad12345"]) end)
    assert output =~ "not found"
  end

  test "stop command stops mission" do
    {:ok, id} = Overmind.run("sleep 60")
    Process.sleep(50)

    output = capture_io(fn -> Overmind.CLI.main(["stop", id]) end)
    assert output =~ "Stopped"
  end

  test "kill command kills mission" do
    {:ok, id} = Overmind.run("sleep 60")
    Process.sleep(50)

    output = capture_io(fn -> Overmind.CLI.main(["kill", id]) end)
    assert output =~ "Killed"
  end
end
