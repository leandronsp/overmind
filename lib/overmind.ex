defmodule Overmind do
  @moduledoc false

  alias Overmind.Mission
  alias Overmind.Mission.Client
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
    restart_policy = Keyword.get(opts, :restart_policy, :never)
    max_restarts = Keyword.get(opts, :max_restarts, 5)
    max_seconds = Keyword.get(opts, :max_seconds, 60)
    backoff_ms = Keyword.get(opts, :backoff_ms, 1000)
    activity_timeout = Keyword.get(opts, :activity_timeout, 0)
    parent = Keyword.get(opts, :parent)

    with :ok <- validate_type(type),
         :ok <- validate_command(command, type),
         :ok <- validate_restart_policy(restart_policy),
         {:ok, resolved_parent} <- validate_parent(parent) do
      start_mission(command, provider, type, cwd, name,
        restart_policy: restart_policy,
        max_restarts: max_restarts,
        max_seconds: max_seconds,
        backoff_ms: backoff_ms,
        activity_timeout: activity_timeout,
        parent: resolved_parent
      )
    end
  end

  defp validate_type(:task), do: :ok
  defp validate_type(:session), do: :ok
  defp validate_type(_), do: {:error, :invalid_type}

  defp validate_command("", :task), do: {:error, :empty_command}
  defp validate_command(_, _), do: :ok

  defp validate_restart_policy(policy) when policy in [:never, :on_failure, :always], do: :ok
  defp validate_restart_policy(_), do: {:error, :invalid_restart_policy}

  defp validate_parent(nil), do: {:ok, nil}

  defp validate_parent(parent_id) do
    resolved = Store.resolve_id(parent_id)

    case Store.lookup(resolved) do
      :not_found -> {:error, :parent_not_found}
      _ -> {:ok, resolved}
    end
  end

  defp start_mission(command, provider, type, cwd, name, extra_opts) do
    id = Mission.generate_id()

    spec =
      {Mission,
       [id: id, command: command, provider: provider, type: type, cwd: cwd, name: name] ++
         extra_opts}

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
        restart_count: Store.lookup_restart_count(id),
        parent: Store.lookup_parent(id),
        children: length(Store.find_children(id)),
        uptime: now - started_at
      }
    end)
  end

  @spec pause(String.t()) :: {:ok, String.t() | nil} | {:error, :not_found | :not_running | :not_session}
  def pause(id), do: id |> Store.resolve_id() |> Client.pause()

  @spec unpause(String.t()) :: :ok | {:error, :not_found | :not_running}
  def unpause(id), do: id |> Store.resolve_id() |> Client.unpause()

  @spec send(String.t(), String.t()) :: :ok | {:error, :not_found | :not_running | :not_session | :paused}
  def send(id, message) do
    id |> Store.resolve_id() |> Client.send_message(message)
  end

  @spec children(String.t()) :: [map()]
  def children(id) do
    resolved = Store.resolve_id(id)
    child_ids = Store.find_children(resolved)
    missions = ps()
    Enum.filter(missions, fn m -> m.id in child_ids end)
  end

  @spec wait(String.t(), non_neg_integer() | nil) :: {:ok, map()} | {:error, :not_found | :timeout}
  def wait(id, timeout \\ nil) do
    id |> Store.resolve_id() |> Client.wait(timeout)
  end

  @spec info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def info(id) do
    id |> Store.resolve_id() |> Client.get_info()
  end

  @spec logs(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def logs(id) do
    id |> Store.resolve_id() |> Client.get_logs()
  end

  @spec raw_events(String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def raw_events(id) do
    id |> Store.resolve_id() |> Client.get_raw_events()
  end

  @spec stop(String.t()) :: :ok | {:error, :not_found | :not_running}
  def stop(id) do
    id |> Store.resolve_id() |> Client.stop()
  end

  @spec kill(String.t()) :: :ok | {:error, :not_found}
  def kill(id) do
    id |> Store.resolve_id() |> Client.kill()
  end

  @spec kill_cascade(String.t()) :: :ok | {:error, :not_found}
  def kill_cascade(id) do
    id |> Store.resolve_id() |> Client.kill_cascade()
  end

  defdelegate format_ps(missions), to: Overmind.Formatter
  defdelegate format_ps_tree(missions), to: Overmind.Formatter
end
