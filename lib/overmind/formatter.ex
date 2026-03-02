defmodule Overmind.Formatter do
  @moduledoc false

  @spec format_ps([map()]) :: String.t()
  def format_ps(missions) do
    lines = Enum.map(missions, fn m -> format_line(m, "") end)
    Enum.join([header() | lines], "\n") <> "\n"
  end

  @spec format_ps_tree([map()]) :: String.t()
  def format_ps_tree(missions) do
    ids_in_list = MapSet.new(missions, & &1.id)
    {roots, children_map} = partition_tree(missions, ids_in_list)
    lines = render_tree(roots, children_map, "")

    Enum.join([header() | lines], "\n") <> "\n"
  end

  # Private helpers

  defp header do
    String.pad_trailing("ID", 12) <>
      String.pad_trailing("NAME", 18) <>
      String.pad_trailing("TYPE", 10) <>
      String.pad_trailing("STATUS", 14) <>
      String.pad_trailing("RESTARTS", 10) <>
      String.pad_trailing("PARENT", 12) <>
      String.pad_trailing("CHILDREN", 10) <>
      String.pad_trailing("UPTIME", 10) <>
      "COMMAND"
  end

  defp format_line(m, prefix) do
    prefix <>
      String.pad_trailing(m.id, 12) <>
      String.pad_trailing(m[:name] || "", 18) <>
      String.pad_trailing(Atom.to_string(m.type), 10) <>
      String.pad_trailing(Atom.to_string(m.status), 14) <>
      String.pad_trailing(Integer.to_string(m[:restart_count] || 0), 10) <>
      String.pad_trailing(m[:parent] || "-", 12) <>
      String.pad_trailing(Integer.to_string(m[:children] || 0), 10) <>
      String.pad_trailing(format_uptime(m.uptime), 10) <>
      m.command
  end

  defp partition_tree(missions, ids_in_list) do
    by_parent = Enum.group_by(missions, & &1[:parent])

    roots =
      Enum.filter(missions, fn m ->
        m[:parent] == nil or not MapSet.member?(ids_in_list, m[:parent])
      end)

    {roots, by_parent}
  end

  defp render_tree(nodes, children_map, prefix) do
    last_idx = length(nodes) - 1

    nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn {node, idx} ->
      is_last = idx == last_idx
      connector = tree_connector(prefix, is_last)
      child_prefix = tree_child_prefix(prefix, is_last)

      line = format_line(node, prefix <> connector)
      kids = Map.get(children_map, node.id, [])
      [line | render_tree(kids, children_map, child_prefix)]
    end)
  end

  defp tree_connector("", _is_last), do: ""
  defp tree_connector(_prefix, _is_last = true), do: "└─ "
  defp tree_connector(_prefix, _is_last = false), do: "├─ "

  defp tree_child_prefix("", _is_last), do: ""
  defp tree_child_prefix(prefix, _is_last = true), do: prefix <> "   "
  defp tree_child_prefix(prefix, _is_last = false), do: prefix <> "│  "

  defp format_uptime(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_uptime(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp format_uptime(seconds), do: "#{div(seconds, 3600)}h"
end
