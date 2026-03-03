defmodule Overmind.TUI.Panels.Missions do
  @moduledoc false

  # Renders the mission list as an ANSI-formatted string.
  # Missions are maps with string keys (from JSON decoding via daemon socket).
  @spec render([map()], non_neg_integer(), non_neg_integer()) :: String.t()
  def render(missions, selected, width) do
    header = render_header(width)
    rows = missions |> Enum.with_index() |> Enum.map(fn {m, i} -> render_row(m, i == selected) end)
    Enum.join([header | rows], "\r\n")
  end

  defp render_header(width) do
    line =
      String.pad_trailing("NAME", 20) <>
        String.pad_trailing("STATUS", 12) <>
        String.pad_trailing("TYPE", 10) <>
        "COMMAND"

    # Bold header, clipped to terminal width
    "\e[1m" <> String.slice(line, 0, width) <> "\e[0m"
  end

  # Reverse video for selected row
  defp render_row(m, _selected = true) do
    "\e[7m" <> format_row(m) <> "\e[0m"
  end

  defp render_row(m, _selected = false) do
    status_color(m["status"]) <> format_row(m) <> "\e[0m"
  end

  defp format_row(m) do
    String.pad_trailing(m["name"] || m["id"] || "", 20) <>
      String.pad_trailing(m["status"] || "", 12) <>
      String.pad_trailing(m["type"] || "", 10) <>
      truncate(m["command"] || "", 40)
  end

  defp status_color("running"), do: "\e[32m"
  defp status_color("crashed"), do: "\e[31m"
  defp status_color("stopped"), do: "\e[33m"
  defp status_color(_), do: ""

  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max - 3) <> "..."
end
