defmodule Overmind.TUI.AppTest do
  use ExUnit.Case

  alias Overmind.TUI.App

  # Suppress TUI rendering output during tests
  setup do
    {:ok, string_io} = StringIO.open("")
    prev_gl = Process.group_leader()
    Process.group_leader(self(), string_io)
    on_exit(fn -> Process.group_leader(self(), prev_gl) end)
    :ok
  end

  describe "start_link/1" do
    test "starts successfully (daemon may not be running — shows error state)" do
      # App starts even when daemon is not reachable; it just sets error state
      {:ok, pid} = App.start_link(skip_stdin: true, name: nil)
      assert Process.alive?(pid)
      GenServer.stop(pid, :normal)
    end
  end

  describe "key handling" do
    test "q key stops the GenServer" do
      {:ok, pid} = App.start_link(skip_stdin: true, name: nil)
      ref = Process.monitor(pid)
      send(pid, {:key, "q"})
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "Ctrl+C stops the GenServer" do
      {:ok, pid} = App.start_link(skip_stdin: true, name: nil)
      ref = Process.monitor(pid)
      send(pid, {:key, "\x03"})
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "unknown keys do not crash the GenServer" do
      {:ok, pid} = App.start_link(skip_stdin: true, name: nil)
      send(pid, {:key, "z"})
      send(pid, {:key, "\t"})
      Process.sleep(50)
      assert Process.alive?(pid)
      GenServer.stop(pid, :normal)
    end
  end
end
