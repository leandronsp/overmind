defmodule Overmind do
  @moduledoc false

  alias Overmind.Session

  @spec run(String.t()) :: {:ok, String.t()} | {:error, term()}
  def run(""), do: {:error, :empty_command}

  def run(command) do
    id = Session.generate_id()
    spec = {Session, id: id, command: command}

    case DynamicSupervisor.start_child(Overmind.SessionSupervisor, spec) do
      {:ok, _pid} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ps() :: [map()]
  def ps do
    now = System.system_time(:second)

    :ets.tab2list(:overmind_sessions)
    |> Enum.filter(fn
      {{:logs, _}, _} -> false
      {_id, _pid, _cmd, _status, _started} -> true
    end)
    |> Enum.map(fn {id, _pid, command, status, started_at} ->
      %{id: id, command: command, status: status, uptime: now - started_at}
    end)
  end

  @spec logs(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def logs(id) do
    Session.get_logs(id)
  end

  @spec stop(String.t()) :: :ok | {:error, :not_found | :not_running}
  def stop(id) do
    Session.signal(id, :sigterm)
  end

  @spec kill(String.t()) :: :ok | {:error, :not_found | :not_running}
  def kill(id) do
    Session.signal(id, :sigkill)
  end
end
