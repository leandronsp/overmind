defmodule Overmind.Ritual do
  @moduledoc false

  @table :overmind_rituals

  @type t :: %{
    id: String.t(),
    name: String.t(),
    cron_expr: String.t(),
    command: String.t(),
    created_at: integer(),
    last_run_at: integer() | nil
  }

  @spec create(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_cron}
  def create(name, cron_expr, command) do
    with :ok <- validate_cron(cron_expr) do
      id = generate_id()
      created_at = System.system_time(:second)
      :ets.insert(@table, {id, name, cron_expr, command, created_at, nil})
      {:ok, id}
    end
  end

  @spec list() :: [t()]
  def list do
    :ets.tab2list(@table)
    |> Enum.filter(&match?({_, _, _, _, _, _}, &1))
    |> Enum.map(&to_map/1)
  end

  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(name) do
    case find_id_by_name(name) do
      nil -> {:error, :not_found}
      id -> :ets.delete(@table, id); :ok
    end
  end

  @spec update_last_run(String.t(), integer()) :: :ok
  def update_last_run(id, timestamp) do
    case :ets.lookup(@table, id) do
      [{^id, name, cron_expr, command, created_at, _}] ->
        :ets.insert(@table, {id, name, cron_expr, command, created_at, timestamp})
        :ok

      [] ->
        :ok
    end
  end

  # Private

  defp find_id_by_name(name) do
    case :ets.match_object(@table, {:_, name, :_, :_, :_, :_}) do
      [{id, ^name, _, _, _, _} | _] -> id
      [] -> nil
    end
  end

  defp validate_cron(expr) do
    if length(String.split(expr)) == 5, do: :ok, else: {:error, :invalid_cron}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
  end

  defp to_map({id, name, cron_expr, command, created_at, last_run_at}) do
    %{
      id: id,
      name: name,
      cron_expr: cron_expr,
      command: command,
      created_at: created_at,
      last_run_at: last_run_at
    }
  end
end
