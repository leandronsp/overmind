defmodule Overmind.Blueprint.DAG do
  @moduledoc false

  # Kahn's algorithm: repeatedly pick nodes with in-degree 0, remove them,
  # and reduce the in-degree of their dependents. If the output list length
  # is less than the input, there is a cycle.

  @spec topo_sort([map()]) :: {:ok, [map()]} | {:error, :cycle}
  def topo_sort(specs) do
    name_to_spec = Map.new(specs, fn s -> {s.name, s} end)
    in_degree = Map.new(specs, fn s -> {s.name, length(s.depends_on)} end)

    # adj maps each dependency to the list of agents that depend on it
    adj = build_adj(specs)

    queue = for {name, 0} <- in_degree, do: name
    do_sort(queue, in_degree, adj, name_to_spec, [])
  end

  defp do_sort([], in_degree, _adj, _names, acc) do
    case Enum.any?(in_degree, fn {_, count} -> count > 0 end) do
      true -> {:error, :cycle}
      false -> {:ok, Enum.reverse(acc)}
    end
  end

  defp do_sort([name | rest], in_degree, adj, names, acc) do
    spec = Map.fetch!(names, name)
    dependents = Map.get(adj, name, [])

    {new_in_degree, new_ready} =
      Enum.reduce(dependents, {in_degree, []}, fn dep, {degrees, ready} ->
        new_count = Map.get(degrees, dep, 0) - 1
        new_ready = if new_count == 0, do: [dep | ready], else: ready
        {Map.put(degrees, dep, new_count), new_ready}
      end)

    do_sort(
      rest ++ new_ready,
      Map.delete(new_in_degree, name),
      adj,
      names,
      [spec | acc]
    )
  end

  defp build_adj(specs) do
    Enum.reduce(specs, %{}, fn spec, acc ->
      Enum.reduce(spec.depends_on, acc, fn dep, a ->
        Map.update(a, dep, [spec.name], &[spec.name | &1])
      end)
    end)
  end
end
