defmodule Overmind.TUI.Panels.Logs do
  @moduledoc false

  # Renders the tail of a mission's log output as an ANSI-formatted string.
  # Shows the most recent lines that fit within the terminal height.
  @spec render(String.t(), String.t() | nil, non_neg_integer(), non_neg_integer()) :: String.t()
  def render(logs, mission, width, height) do
    header = render_header(mission, width)
    body = render_body(logs, height - 3)
    Enum.join([header | body], "\r\n")
  end

  defp render_header(nil, _width) do
    "\e[1mLogs\e[0m  \e[2m[t] missions  [r] refresh  [q] quit\e[0m"
  end

  defp render_header(mission, _width) do
    "\e[1mLogs: #{mission}\e[0m  \e[2m[t] missions  [r] refresh  [q] quit\e[0m"
  end

  defp render_body("", _limit), do: ["\e[2m  (no logs yet)\e[0m"]

  defp render_body(logs, limit) do
    logs
    |> String.split("\n")
    |> Enum.take(-limit)
  end
end
