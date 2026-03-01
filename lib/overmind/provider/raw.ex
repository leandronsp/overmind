defmodule Overmind.Provider.Raw do
  @moduledoc false
  @behaviour Overmind.Provider

  @spec build_command(String.t()) :: String.t()
  def build_command(command) do
    escaped = String.replace(command, "'", "'\\''")
    "sh -c '#{escaped}'"
  end

  @spec build_session_command() :: String.t()
  def build_session_command, do: "cat"

  @spec build_input_message(String.t()) :: String.t()
  def build_input_message(msg), do: msg <> "\n"

  @spec parse_line(String.t()) :: {Overmind.Provider.event(), nil}
  def parse_line(line), do: {{:plain, line}, nil}

  @spec format_for_logs(Overmind.Provider.event()) :: String.t()
  def format_for_logs({:plain, text}), do: text <> "\n"
end
