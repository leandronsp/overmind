defmodule Overmind.Blueprint do
  @moduledoc false

  alias Overmind.Blueprint.{DAG, Parser}

  # Reads a blueprint TOML file and returns the list of agent specs.
  @spec agents(String.t()) :: {:ok, [map()]} | {:error, term()}
  def agents(path) do
    with {:ok, content} <- File.read(path),
         {:ok, specs} <- Parser.parse(content) do
      {:ok, specs}
    end
  end

  # Reads a blueprint TOML file, resolves dependency order via DAG,
  # and spawns each agent in topological order. Waits for each agent
  # to finish before starting the next to honour depends_on constraints.
  # Returns the list of %{name, id} maps in execution order.
  @spec apply(String.t()) :: {:ok, [%{name: String.t(), id: String.t()}]} | {:error, term()}
  def apply(path) do
    with {:ok, content} <- File.read(path),
         {:ok, specs} <- Parser.parse(content),
         {:ok, ordered} <- DAG.topo_sort(specs) do
      spawn_ordered(ordered)
    end
  end

  defp spawn_ordered(ordered) do
    Enum.reduce_while(ordered, {:ok, []}, fn spec, {:ok, acc} ->
      opts =
        [provider: spec.provider, type: spec.type, restart_policy: spec.restart_policy]
        |> maybe_add_cwd(spec.cwd)
        |> Keyword.put(:name, spec.name)

      case Overmind.run(spec.command, opts) do
        {:ok, id} ->
          case Overmind.wait(id) do
            {:ok, _} -> {:cont, {:ok, [%{name: spec.name, id: id} | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end)
  end

  defp maybe_add_cwd(opts, nil), do: opts
  defp maybe_add_cwd(opts, cwd), do: Keyword.put(opts, :cwd, cwd)
end
