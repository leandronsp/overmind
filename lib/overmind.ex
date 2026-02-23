defmodule Overmind do
  @moduledoc false

  alias Overmind.Mission

  @spec run(String.t(), module()) :: {:ok, String.t()} | {:error, term()}
  def run(command, provider \\ Overmind.Provider.Raw)

  def run("", _provider), do: {:error, :empty_command}

  def run(command, provider) do
    id = Mission.generate_id()
    spec = {Mission, id: id, command: command, provider: provider}

    case DynamicSupervisor.start_child(Overmind.MissionSupervisor, spec) do
      {:ok, _pid} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ps() :: [map()]
  def ps do
    now = System.system_time(:second)

    :ets.tab2list(:overmind_missions)
    |> Enum.filter(fn
      {{:logs, _}, _} -> false
      {{:raw_events, _}, _} -> false
      {_id, _pid, _cmd, _status, _started} -> true
    end)
    |> Enum.map(fn {id, _pid, command, status, started_at} ->
      %{id: id, command: command, status: status, uptime: now - started_at}
    end)
  end

  @spec logs(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def logs(id) do
    Mission.get_logs(id)
  end

  @spec raw_events(String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def raw_events(id) do
    Mission.get_raw_events(id)
  end

  @spec stop(String.t()) :: :ok | {:error, :not_found | :not_running}
  def stop(id) do
    Mission.stop(id)
  end

  @spec kill(String.t()) :: :ok | {:error, :not_found}
  def kill(id) do
    Mission.kill(id)
  end
end
