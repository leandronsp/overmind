defmodule Overmind.Provider do
  @moduledoc false

  @type event ::
          {:text, String.t()}
          | {:tool_use, String.t()}
          | {:thinking, String.t()}
          | {:system, map()}
          | {:tool_result, map()}
          | {:result, map()}
          | {:plain, String.t()}
          | {:ignored, map()}

  @callback build_command(String.t()) :: String.t()
  @callback build_session_command(keyword()) :: String.t()
  @callback build_input_message(String.t()) :: String.t()
  @callback parse_line(String.t()) :: {event(), map() | nil}
  @callback format_for_logs(event()) :: String.t()
end
