defmodule Overmind.TUI do
  @moduledoc false

  # Entry point for the TUI. Called from Entrypoint when invoked as __tui__.
  # Sets the terminal to raw mode (no echo, single-char reads), starts the
  # App GenServer, waits for it to exit, then restores terminal state.
  @spec run() :: :ok
  def run do
    hide_cursor()
    set_raw_mode()
    {:ok, pid} = Overmind.TUI.App.start_link()
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end

    restore_terminal()
    :ok
  end

  defp hide_cursor, do: IO.write("\e[?25l")

  defp set_raw_mode do
    # raw: disable line buffering; -echo: suppress keystroke echo
    System.cmd("stty", ["raw", "-echo"], into: "")
  end

  defp restore_terminal do
    # Show cursor, clear screen, move home, restore sane terminal settings
    IO.write("\e[?25h\e[2J\e[H")
    System.cmd("stty", ["sane"], into: "")
    IO.puts("")
  end
end
