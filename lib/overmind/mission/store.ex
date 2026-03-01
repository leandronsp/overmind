defmodule Overmind.Mission.Store do
  @moduledoc false

  @table :overmind_missions

  @type lookup_result ::
          {:running, pid(), String.t(), integer()}
          | {:restarting, pid(), String.t(), integer()}
          | {:exited, atom(), String.t(), integer()}
          | :not_found

  @spec lookup(String.t()) :: lookup_result()
  def lookup(id) do
    case :ets.lookup(@table, id) do
      [{^id, pid, command, :running, started_at}] ->
        {:running, pid, command, started_at}

      [{^id, pid, command, :restarting, started_at}] ->
        if Process.alive?(pid),
          do: {:restarting, pid, command, started_at},
          else: {:exited, :restarting, command, started_at}

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

  @spec insert_type(String.t(), atom()) :: true
  def insert_type(id, type) do
    :ets.insert(@table, {{:type, id}, type})
  end

  @spec lookup_type(String.t()) :: atom()
  def lookup_type(id) do
    case :ets.lookup(@table, {:type, id}) do
      [{{:type, ^id}, type}] -> type
      [] -> :task
    end
  end

  @spec insert_session_id(String.t(), String.t()) :: true
  def insert_session_id(id, session_id) do
    :ets.insert(@table, {{:session_id, id}, session_id})
  end

  @spec lookup_session_id(String.t()) :: String.t() | nil
  def lookup_session_id(id) do
    case :ets.lookup(@table, {:session_id, id}) do
      [{{:session_id, ^id}, session_id}] -> session_id
      [] -> nil
    end
  end

  @spec insert_attached(String.t(), boolean()) :: true
  def insert_attached(id, attached) do
    :ets.insert(@table, {{:attached, id}, attached})
  end

  @spec lookup_attached(String.t()) :: boolean()
  def lookup_attached(id) do
    case :ets.lookup(@table, {:attached, id}) do
      [{{:attached, ^id}, attached}] -> attached
      [] -> false
    end
  end

  @spec insert_name(String.t(), String.t()) :: true
  def insert_name(id, name) do
    :ets.insert(@table, {{:name, id}, name})
  end

  @spec lookup_name(String.t()) :: String.t() | nil
  def lookup_name(id) do
    case :ets.lookup(@table, {:name, id}) do
      [{{:name, ^id}, name}] -> name
      [] -> nil
    end
  end

  @spec find_by_name(String.t()) :: String.t() | nil
  def find_by_name(name) do
    case :ets.match_object(@table, {{:name, :_}, name}) do
      [{{:name, id}, ^name} | _] -> id
      [] -> nil
    end
  end

  @spec resolve_id(String.t()) :: String.t()
  def resolve_id(id_or_name) do
    case lookup(id_or_name) do
      :not_found ->
        case find_by_name(id_or_name) do
          nil -> id_or_name
          id -> id
        end

      _ ->
        id_or_name
    end
  end

  @spec insert_cwd(String.t(), String.t()) :: true
  def insert_cwd(id, cwd) do
    :ets.insert(@table, {{:cwd, id}, cwd})
  end

  @spec lookup_cwd(String.t()) :: String.t() | nil
  def lookup_cwd(id) do
    case :ets.lookup(@table, {:cwd, id}) do
      [{{:cwd, ^id}, cwd}] -> cwd
      [] -> nil
    end
  end

  @spec insert_restart_policy(String.t(), atom()) :: true
  def insert_restart_policy(id, policy) do
    :ets.insert(@table, {{:restart_policy, id}, policy})
  end

  @spec lookup_restart_policy(String.t()) :: atom()
  def lookup_restart_policy(id) do
    case :ets.lookup(@table, {:restart_policy, id}) do
      [{{:restart_policy, ^id}, policy}] -> policy
      [] -> :never
    end
  end

  @spec insert_restart_count(String.t(), non_neg_integer()) :: true
  def insert_restart_count(id, count) do
    :ets.insert(@table, {{:restart_count, id}, count})
  end

  @spec lookup_restart_count(String.t()) :: non_neg_integer()
  def lookup_restart_count(id) do
    case :ets.lookup(@table, {:restart_count, id}) do
      [{{:restart_count, ^id}, count}] -> count
      [] -> 0
    end
  end

  @spec insert_last_activity(String.t(), integer()) :: true
  def insert_last_activity(id, timestamp) do
    :ets.insert(@table, {{:last_activity, id}, timestamp})
  end

  @spec lookup_last_activity(String.t()) :: integer() | nil
  def lookup_last_activity(id) do
    case :ets.lookup(@table, {:last_activity, id}) do
      [{{:last_activity, ^id}, ts}] -> ts
      [] -> nil
    end
  end

  @spec cleanup(String.t()) :: :ok
  def cleanup(id) do
    :ets.delete(@table, id)
    :ets.delete(@table, {:logs, id})
    :ets.delete(@table, {:raw_events, id})
    :ets.delete(@table, {:type, id})
    :ets.delete(@table, {:session_id, id})
    :ets.delete(@table, {:attached, id})
    :ets.delete(@table, {:cwd, id})
    :ets.delete(@table, {:name, id})
    :ets.delete(@table, {:restart_policy, id})
    :ets.delete(@table, {:restart_count, id})
    :ets.delete(@table, {:last_activity, id})
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
