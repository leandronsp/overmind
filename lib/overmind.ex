defmodule Overmind do
  @moduledoc false

  alias Overmind.Mission
  alias Overmind.Mission.Store

  @spec run(String.t(), keyword() | module()) :: {:ok, String.t()} | {:error, term()}
  def run(command, opts \\ [])

  def run(command, provider) when is_atom(provider) do
    run(command, provider: provider)
  end

  def run(command, opts) when is_list(opts) do
    provider = Keyword.get(opts, :provider, Overmind.Provider.Raw)
    type = Keyword.get(opts, :type, :task)
    cwd = Keyword.get(opts, :cwd)
    name = Keyword.get(opts, :name)

    with :ok <- validate_type(type),
         :ok <- validate_command(command, type) do
      start_mission(command, provider, type, cwd, name)
    end
  end

  defp validate_type(:task), do: :ok
  defp validate_type(:session), do: :ok
  defp validate_type(_), do: {:error, :invalid_type}

  defp validate_command("", :task), do: {:error, :empty_command}
  defp validate_command(_, _), do: :ok

  defp start_mission(command, provider, type, cwd, name) do
    id = Mission.generate_id()
    spec = {Mission, id: id, command: command, provider: provider, type: type, cwd: cwd, name: name}

    case DynamicSupervisor.start_child(Overmind.MissionSupervisor, spec) do
      {:ok, _pid} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ps() :: [map()]
  def ps do
    now = System.system_time(:second)

    Store.list_all()
    |> Enum.map(fn {id, _pid, command, status, started_at} ->
      %{
        id: id,
        name: Store.lookup_name(id),
        command: command,
        status: status,
        type: Store.lookup_type(id),
        session_id: Store.lookup_session_id(id),
        attached: Store.lookup_attached(id),
        uptime: now - started_at
      }
    end)
  end

  @spec pause(String.t()) :: {:ok, String.t() | nil} | {:error, :not_found | :not_running | :not_session}
  def pause(id), do: id |> Store.resolve_id() |> Mission.pause()

  @spec unpause(String.t()) :: :ok | {:error, :not_found | :not_running}
  def unpause(id), do: id |> Store.resolve_id() |> Mission.unpause()

  @spec send(String.t(), String.t()) :: :ok | {:error, :not_found | :not_running | :not_session | :paused}
  def send(id, message) do
    id |> Store.resolve_id() |> Mission.send_message(message)
  end

  @spec logs(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def logs(id) do
    id |> Store.resolve_id() |> Mission.get_logs()
  end

  @spec raw_events(String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def raw_events(id) do
    id |> Store.resolve_id() |> Mission.get_raw_events()
  end

  @spec stop(String.t()) :: :ok | {:error, :not_found | :not_running}
  def stop(id) do
    id |> Store.resolve_id() |> Mission.stop()
  end

  @spec kill(String.t()) :: :ok | {:error, :not_found}
  def kill(id) do
    id |> Store.resolve_id() |> Mission.kill()
  end

  @spec format_ps([map()]) :: String.t()
  def format_ps(missions) do
    header =
      String.pad_trailing("ID", 12) <>
        String.pad_trailing("NAME", 18) <>
        String.pad_trailing("TYPE", 10) <>
        String.pad_trailing("STATUS", 12) <>
        String.pad_trailing("UPTIME", 10) <>
        "COMMAND"

    lines =
      Enum.map(missions, fn m ->
        String.pad_trailing(m.id, 12) <>
          String.pad_trailing(m[:name] || "", 18) <>
          String.pad_trailing(Atom.to_string(m.type), 10) <>
          String.pad_trailing(Atom.to_string(m.status), 12) <>
          String.pad_trailing(format_uptime(m.uptime), 10) <>
          m.command
      end)

    Enum.join([header | lines], "\n") <> "\n"
  end

  defp format_uptime(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_uptime(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp format_uptime(seconds), do: "#{div(seconds, 3600)}h"
end
