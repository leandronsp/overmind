defmodule Overmind.Blueprint.DAG do
  @moduledoc false

  @spec topo_sort([map()]) :: {:ok, [map()]} | {:error, :cycle}
  def topo_sort(specs) do
    by_name = Map.new(specs, &{&1.name, &1})

    in_degree =
      Map.new(specs, fn spec -> {spec.name, length(spec.depends_on)} end)

    queue =
      in_degree
      |> Enum.filter(fn {_name, deg} -> deg == 0 end)
      |> Enum.map(fn {name, _} -> name end)
      |> Enum.sort()

    kahn(queue, in_degree, by_name, specs, [])
  end

  # Kahn's algorithm: process nodes with zero in-degree, decrement dependents.
  defp kahn([], _in_degree, _by_name, specs, result) do
    if length(result) == length(specs) do
      {:ok, Enum.reverse(result)}
    else
      {:error, :cycle}
    end
  end

  defp kahn([current | rest], in_degree, by_name, specs, result) do
    spec = Map.fetch!(by_name, current)

    # Find specs that depend on current, decrement their in-degree
    {new_queue, new_in_degree} =
      Enum.reduce(specs, {rest, in_degree}, fn s, {q, deg} ->
        if current in s.depends_on do
          new_deg = Map.update!(deg, s.name, &(&1 - 1))

          if new_deg[s.name] == 0 do
            {q ++ [s.name], new_deg}
          else
            {q, new_deg}
          end
        else
          {q, deg}
        end
      end)

    kahn(new_queue, new_in_degree, by_name, specs, [spec | result])
  end
end
