defmodule Overmind.Provider.TestClaude do
  @moduledoc false
  @behaviour Overmind.Provider

  def build_command(command), do: command
  def build_session_command(_opts \\ []), do: "cat"
  def build_input_message(msg), do: Overmind.Provider.Claude.build_input_message(msg)
  def parse_line(line), do: Overmind.Provider.Claude.parse_line(line)
  def format_for_logs(event), do: Overmind.Provider.Claude.format_for_logs(event)
end
