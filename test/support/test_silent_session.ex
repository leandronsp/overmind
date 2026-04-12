defmodule Overmind.Provider.TestSilentSession do
  @moduledoc false
  # Test provider for sessions that accept input but produce no output.
  # Used for timeout and exit tests where we don't want echoed input.
  @behaviour Overmind.Provider

  def build_command(command, _opts \\ []), do: command
  def build_session_command(_opts \\ []), do: "sleep 60"
  def build_input_message(msg), do: Overmind.Provider.Claude.build_input_message(msg)
  def parse_line(line), do: Overmind.Provider.Claude.parse_line(line)
  def format_for_logs(event), do: Overmind.Provider.Claude.format_for_logs(event)
end
