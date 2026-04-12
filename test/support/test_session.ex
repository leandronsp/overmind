defmodule Overmind.Provider.TestSession do
  @moduledoc false
  # Test provider for session missions that reads a line from stdin
  # then outputs a result event. Used for send_and_wait tests.
  @behaviour Overmind.Provider

  @result_script ~s(sh -c 'read line; echo "{\\\"type\\\":\\\"result\\\",\\\"result\\\":\\\"Done\\\",\\\"duration_ms\\\":100,\\\"cost_usd\\\":0.01,\\\"is_error\\\":false}"')

  def build_command(command, _opts \\ []), do: command
  def build_session_command(_opts \\ []), do: @result_script
  def build_input_message(msg), do: Overmind.Provider.Claude.build_input_message(msg)
  def parse_line(line), do: Overmind.Provider.Claude.parse_line(line)
  def format_for_logs(event), do: Overmind.Provider.Claude.format_for_logs(event)
end
