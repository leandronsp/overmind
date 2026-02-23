defmodule Overmind.Provider.Claude do
  @moduledoc false
  @behaviour Overmind.Provider

  @spec build_command(String.t()) :: String.t()
  def build_command(prompt) do
    escaped = String.replace(prompt, "'", "'\\''")
    "claude -p '#{escaped}' --output-format stream-json --verbose"
  end

  @spec parse_line(String.t()) :: {Overmind.Provider.event(), map() | nil}
  def parse_line(line) do
    case JSON.decode(line) do
      {:ok, map} -> parse_event(map)
      {:error, _} -> {{:plain, line}, nil}
    end
  end

  @spec format_for_logs(Overmind.Provider.event()) :: String.t()
  def format_for_logs({:text, text}), do: text <> "\n"
  def format_for_logs({:plain, text}), do: text <> "\n"
  def format_for_logs({:tool_use, _}), do: ""
  def format_for_logs({:result, _}), do: ""
  def format_for_logs({:thinking, _}), do: ""
  def format_for_logs({:system, _}), do: ""
  def format_for_logs({:tool_result, _}), do: ""
  def format_for_logs({:ignored, _}), do: ""

  defp parse_event(%{"type" => "system"} = raw) do
    {{:system, Map.delete(raw, "type")}, raw}
  end

  defp parse_event(%{"type" => "assistant", "message" => %{"content" => content}} = raw) do
    {pick_content_block(content, raw), raw}
  end

  defp parse_event(%{"type" => "user", "message" => %{"content" => content}} = raw) do
    block = Enum.find(content, &(&1["type"] == "tool_result"))
    parse_user_content(block, raw)
  end

  defp parse_event(%{"type" => "result", "is_error" => true} = raw) do
    text = raw["error"] || raw["result"] || ""

    {{:result,
      %{
        text: text,
        duration_ms: raw["duration_ms"],
        cost_usd: raw["cost_usd"]
      }}, raw}
  end

  defp parse_event(%{"type" => "result"} = raw) do
    {{:result,
      %{
        text: raw["result"] || "",
        duration_ms: raw["duration_ms"],
        cost_usd: raw["cost_usd"]
      }}, raw}
  end

  defp parse_event(raw) do
    {{:ignored, raw}, raw}
  end

  defp parse_user_content(nil, raw), do: {{:ignored, raw}, raw}
  defp parse_user_content(block, raw), do: {{:tool_result, Map.delete(block, "type")}, raw}

  defp pick_content_block(content, raw) do
    text_block = Enum.find(content, &(&1["type"] == "text"))
    tool_block = Enum.find(content, &(&1["type"] == "tool_use"))
    thinking_block = Enum.find(content, &(&1["type"] == "thinking"))

    cond do
      text_block -> {:text, text_block["text"]}
      tool_block -> {:tool_use, tool_block["name"]}
      thinking_block -> {:thinking, thinking_block["thinking"]}
      true -> {:ignored, raw}
    end
  end
end
