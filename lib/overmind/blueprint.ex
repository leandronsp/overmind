defmodule Overmind.Blueprint do
  @moduledoc false

  alias Overmind.Blueprint.{DAG, Parser}

  @type agent_result :: %{name: String.t(), id: String.t(), status: atom(), exit_code: non_neg_integer() | nil}

  @spec agents(String.t()) :: {:ok, [Parser.agent_spec()]} | {:error, term()}
  def agents(path) do
    with {:ok, content} <- read_file(path),
         {:ok, specs} <- Parser.parse(content) do
      {:ok, specs}
    end
  end

  @spec apply(String.t()) :: {:ok, [agent_result()]} | {:error, map()}
  def apply(path) do
    with {:ok, content} <- read_file(path),
         {:ok, specs} <- Parser.parse(content),
         {:ok, sorted} <- DAG.topo_sort(specs) do
      run_pipeline(sorted, [])
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :enoent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_pipeline([], completed), do: {:ok, Enum.reverse(completed)}

  defp run_pipeline([spec | rest], completed) do
    opts = build_opts(spec, completed)

    case Overmind.run(spec.command, opts) do
      {:ok, id} ->
        {:ok, wait_result} = Overmind.wait(id)
        exit_code = Overmind.Mission.Store.lookup_exit_code(id)

        result = %{
          name: spec.name,
          id: id,
          status: wait_result.status,
          exit_code: exit_code
        }

        handle_result(result, rest, completed)

      {:error, reason} ->
        {:error, %{reason: reason, agent: spec.name, completed: Enum.reverse(completed)}}
    end
  end

  defp handle_result(%{status: :stopped} = result, rest, completed) do
    run_pipeline(rest, [result | completed])
  end

  defp handle_result(result, _rest, completed) do
    {:error, %{reason: :non_zero_exit, agent: result.name, completed: Enum.reverse(completed)}}
  end

  defp build_opts(spec, completed) do
    [provider: spec.provider, type: spec.type, name: spec.name, restart_policy: spec.restart_policy]
    |> maybe_add(:cwd, spec.cwd)
    |> maybe_add_parent(spec.depends_on, completed)
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, val), do: Keyword.put(opts, key, val)

  # First dependency becomes parent (known limitation: only one parent supported)
  defp maybe_add_parent(opts, [], _completed), do: opts

  defp maybe_add_parent(opts, [first_dep | _], completed) do
    case Enum.find(completed, fn r -> r.name == first_dep end) do
      %{id: parent_id} -> Keyword.put(opts, :parent, parent_id)
      nil -> opts
    end
  end
end
