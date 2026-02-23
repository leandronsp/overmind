defmodule Overmind.Mission.Store do
  @moduledoc false

  @table :overmind_missions

  @type lookup_result ::
          {:running, pid(), String.t(), integer()}
          | {:exited, atom(), String.t(), integer()}
          | :not_found

  @spec lookup(String.t()) :: lookup_result()
  def lookup(id) do
    case :ets.lookup(@table, id) do
      [{^id, pid, command, :running, started_at}] ->
        {:running, pid, command, started_at}

      [{^id, _pid, command, status, started_at}] ->
        {:exited, status, command, started_at}

      [] ->
        :not_found
    end
  end

  @spec safe_call(pid(), term()) :: {:ok, term()} | :dead
  def safe_call(pid, message) do
    {:ok, GenServer.call(pid, message)}
  catch
    :exit, _ -> :dead
  end

  @spec insert(String.t(), {pid(), String.t(), atom(), integer()}) :: true
  def insert(id, {pid, command, status, started_at}) do
    :ets.insert(@table, {id, pid, command, status, started_at})
  end

  @spec persist_after_exit(String.t(), String.t(), [map()]) :: :ok
  def persist_after_exit(id, logs, raw_events) do
    :ets.insert(@table, {{:logs, id}, logs})
    :ets.insert(@table, {{:raw_events, id}, raw_events})
    :ok
  end

  @spec stored_logs(String.t()) :: String.t()
  def stored_logs(id) do
    case :ets.lookup(@table, {:logs, id}) do
      [{{:logs, ^id}, logs}] -> logs
      [] -> ""
    end
  end

  @spec stored_raw_events(String.t()) :: [map()]
  def stored_raw_events(id) do
    case :ets.lookup(@table, {:raw_events, id}) do
      [{{:raw_events, ^id}, events}] -> events
      [] -> []
    end
  end

  @spec cleanup(String.t()) :: :ok
  def cleanup(id) do
    :ets.delete(@table, id)
    :ets.delete(@table, {:logs, id})
    :ets.delete(@table, {:raw_events, id})
    :ok
  end

  @spec list_all() :: [{String.t(), pid(), String.t(), atom(), integer()}]
  def list_all do
    :ets.tab2list(@table)
    |> Enum.filter(fn
      {id, _pid, _cmd, _status, _started} when is_binary(id) -> true
      _ -> false
    end)
  end
end
