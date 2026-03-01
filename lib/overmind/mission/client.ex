defmodule Overmind.Mission.Client do
  @moduledoc false
  # Client API for interacting with missions. Routes to the live GenServer
  # process for running/restarting missions, or reads from ETS for exited ones.
  # All functions accept either a mission id or agent name (resolved via Store).

  alias Overmind.Mission.Store

  @spec get_logs(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_logs(id) do
    case Store.lookup(id) do
      {:running, pid, _, _} -> fetch_from_process(pid, :get_logs, "")
      {:restarting, pid, _, _} -> fetch_from_process(pid, :get_logs, "")
      {:exited, _, _, _} -> {:ok, Store.stored_logs(id)}
      :not_found -> {:error, :not_found}
    end
  end

  @spec get_raw_events(String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def get_raw_events(id) do
    case Store.lookup(id) do
      {:running, pid, _, _} -> fetch_from_process(pid, :get_raw_events, [])
      {:restarting, pid, _, _} -> fetch_from_process(pid, :get_raw_events, [])
      {:exited, _, _, _} -> {:ok, Store.stored_raw_events(id)}
      :not_found -> {:error, :not_found}
    end
  end

  @spec stop(String.t()) :: :ok | {:error, :not_found | :not_running}
  def stop(id) do
    case Store.lookup(id) do
      {:running, pid, _, _} -> signal_process(pid, {:stop, :sigterm}, :not_running)
      {:restarting, pid, _, _} -> signal_process(pid, {:stop, :sigterm}, :not_running)
      {:exited, _, _, _} -> {:error, :not_running}
      :not_found -> {:error, :not_found}
    end
  end

  @spec kill(String.t()) :: :ok | {:error, :not_found}
  def kill(id) do
    case Store.lookup(id) do
      {:running, pid, _, _} -> kill_running(pid, id)
      {:restarting, pid, _, _} -> kill_running(pid, id)
      {:exited, _, _, _} -> Store.cleanup(id)
      :not_found -> {:error, :not_found}
    end
  end

  @spec send_message(String.t(), String.t()) :: :ok | {:error, :not_found | :not_running | :not_session | :paused}
  def send_message(id, message) do
    case {Store.lookup(id), Store.lookup_type(id)} do
      {:not_found, _} -> {:error, :not_found}
      {{:exited, _, _, _}, _} -> {:error, :not_running}
      {{:restarting, _, _, _}, _} -> {:error, :not_running}
      {{:running, _pid, _, _}, :task} -> {:error, :not_session}
      {{:running, pid, _, _}, :session} -> checked_send(id, pid, message)
    end
  end

  @spec pause(String.t()) :: {:ok, String.t() | nil} | {:error, :not_found | :not_running | :not_session}
  def pause(id) do
    case {Store.lookup(id), Store.lookup_type(id)} do
      {:not_found, _} -> {:error, :not_found}
      {{:exited, _, _, _}, _} -> {:error, :not_running}
      {{:restarting, _, _, _}, _} -> {:error, :not_running}
      {{:running, _pid, _, _}, :task} -> {:error, :not_session}
      {{:running, pid, _, _}, :session} ->
        case Store.safe_call(pid, :pause) do
          {:ok, session_id} -> {:ok, session_id}
          :dead -> {:error, :not_running}
        end
    end
  end

  @spec unpause(String.t()) :: :ok | {:error, :not_found | :not_running}
  def unpause(id) do
    case Store.lookup(id) do
      :not_found -> {:error, :not_found}
      {:exited, _, _, _} -> {:error, :not_running}
      {:running, pid, _, _} ->
        case Store.safe_call(pid, :unpause) do
          {:ok, :ok} -> :ok
          :dead -> {:error, :not_running}
        end
    end
  end

  @spec get_info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_info(id) do
    case Store.lookup(id) do
      {:running, pid, command, started_at} ->
        {:ok, build_info(id, command, :running, started_at, fetch_os_pid(pid))}

      {:restarting, _pid, command, started_at} ->
        {:ok, build_info(id, command, :restarting, started_at, nil)}

      {:exited, status, command, started_at} ->
        {:ok, build_info(id, command, status, started_at, nil)}

      :not_found ->
        {:error, :not_found}
    end
  end

  # Private helpers

  defp build_info(id, command, status, started_at, os_pid) do
    %{
      id: id,
      name: Store.lookup_name(id),
      command: command,
      status: status,
      started_at: started_at,
      os_pid: os_pid,
      type: Store.lookup_type(id),
      cwd: Store.lookup_cwd(id),
      restart_policy: Store.lookup_restart_policy(id),
      restart_count: Store.lookup_restart_count(id),
      last_activity: Store.lookup_last_activity(id)
    }
  end

  defp fetch_from_process(pid, message, fallback) do
    case Store.safe_call(pid, message) do
      {:ok, value} -> {:ok, value}
      :dead -> {:ok, fallback}
    end
  end

  defp signal_process(pid, message, error_on_dead) do
    case Store.safe_call(pid, message) do
      {:ok, result} -> result
      :dead -> {:error, error_on_dead}
    end
  end

  defp kill_running(pid, id) do
    case Store.safe_call(pid, {:kill, :sigkill}) do
      {:ok, result} -> result
      :dead -> Store.cleanup(id)
    end
  end

  defp fetch_os_pid(pid) do
    case Store.safe_call(pid, :get_os_pid) do
      {:ok, os_pid} -> os_pid
      :dead -> nil
    end
  end

  # Paused = human attached via CLI (attach command). Reject programmatic
  # sends while a human is interacting to avoid conflicting input.
  defp checked_send(id, pid, message) do
    case Store.lookup_attached(id) do
      true -> {:error, :paused}
      false ->
        GenServer.cast(pid, {:send, message})
        :ok
    end
  end
end
