defmodule Overmind.TUI.Keybindings do
  @moduledoc false

  @type action ::
          :quit
          | :nav_down
          | :nav_up
          | :show_logs
          | :show_missions
          | :show_help
          | :refresh
          | :unknown

  @spec handle(String.t() | :eof) :: action()
  def handle("q"), do: :quit
  # Ctrl+C in raw mode sends \x03 instead of SIGINT
  def handle("\x03"), do: :quit
  def handle(:eof), do: :quit
  def handle("j"), do: :nav_down
  def handle("k"), do: :nav_up
  def handle("l"), do: :show_logs
  # Enter key in raw mode
  def handle("\r"), do: :show_logs
  def handle("t"), do: :show_missions
  def handle("?"), do: :show_help
  def handle("r"), do: :refresh
  def handle(_), do: :unknown
end
