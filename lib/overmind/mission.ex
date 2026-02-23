defmodule Overmind.Mission do
  @moduledoc false
  use GenServer

  alias Overmind.Mission.Store

  defstruct [
    :id,
    :command,
    :port,
    :os_pid,
    :started_at,
    :provider,
    logs: "",
    line_buffer: "",
    raw_events: [],
    stopping: false
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          command: String.t(),
          port: port() | nil,
          os_pid: non_neg_integer(),
          started_at: integer(),
          provider: module(),
          logs: String.t(),
          line_buffer: String.t(),
          raw_events: [map()],
          stopping: boolean()
        }

  @spec generate_id() :: String.t()
  def generate_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end

  def child_spec(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    command = Keyword.fetch!(opts, :command)
    provider = Keyword.get(opts, :provider, Overmind.Provider.Raw)
    GenServer.start_link(__MODULE__, %{id: id, command: command, provider: provider})
  end

  @spec get_logs(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_logs(id) do
    case Store.lookup(id) do
      {:running, pid, _, _} -> fetch_from_process(pid, :get_logs, "")
      {:exited, _, _, _} -> {:ok, Store.stored_logs(id)}
      :not_found -> {:error, :not_found}
    end
  end

  @spec get_raw_events(String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def get_raw_events(id) do
    case Store.lookup(id) do
      {:running, pid, _, _} -> fetch_from_process(pid, :get_raw_events, [])
      {:exited, _, _, _} -> {:ok, Store.stored_raw_events(id)}
      :not_found -> {:error, :not_found}
    end
  end

  @spec stop(String.t()) :: :ok | {:error, :not_found | :not_running}
  def stop(id) do
    case Store.lookup(id) do
      {:running, pid, _, _} -> signal_process(pid, {:stop, :sigterm}, :not_running)
      {:exited, _, _, _} -> {:error, :not_running}
      :not_found -> {:error, :not_found}
    end
  end

  @spec kill(String.t()) :: :ok | {:error, :not_found}
  def kill(id) do
    case Store.lookup(id) do
      {:running, pid, _, _} -> kill_running(pid, id)
      {:exited, _, _, _} -> Store.cleanup(id)
      :not_found -> {:error, :not_found}
    end
  end

  @spec get_info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_info(id) do
    case Store.lookup(id) do
      {:running, pid, command, started_at} ->
        os_pid = fetch_os_pid(pid)
        {:ok, %{id: id, command: command, status: :running, started_at: started_at, os_pid: os_pid}}

      {:exited, status, command, started_at} ->
        {:ok, %{id: id, command: command, status: status, started_at: started_at, os_pid: nil}}

      :not_found ->
        {:error, :not_found}
    end
  end

  # Private helpers for client API

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

  # GenServer callbacks

  @impl true
  def init(%{id: id, command: command, provider: provider}) do
    port_command = provider.build_command(command) <> " < /dev/null"
    port = Port.open({:spawn, port_command}, [:binary, :exit_status, :stderr_to_stdout])
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    now = System.system_time(:second)
    Store.insert(id, {self(), command, :running, now})

    {:ok,
     %__MODULE__{
       id: id,
       command: command,
       port: port,
       os_pid: os_pid,
       started_at: now,
       provider: provider
     }}
  end

  @impl true
  def handle_call(:get_os_pid, _from, state) do
    {:reply, state.os_pid, state}
  end

  @impl true
  def handle_call(:get_logs, _from, state) do
    {:reply, state.logs, state}
  end

  @impl true
  def handle_call(:get_raw_events, _from, state) do
    {:reply, state.raw_events, state}
  end

  @impl true
  def handle_call({:stop, :sigterm}, _from, state) do
    System.cmd("kill", ["-15", Integer.to_string(state.os_pid)])
    {:reply, :ok, %{state | stopping: true}}
  end

  @impl true
  def handle_call({:kill, :sigkill}, _from, state) do
    System.cmd("kill", ["-9", Integer.to_string(state.os_pid)])
    Store.cleanup(state.id)
    {:stop, :normal, :ok, %{state | port: nil}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {lines, remainder} = split_lines(state.line_buffer <> data)

    {logs_append, new_raw_events} =
      Enum.reduce(lines, {"", []}, fn line, {logs_acc, events_acc} ->
        {event, raw} = state.provider.parse_line(line)
        formatted = state.provider.format_for_logs(event)
        {logs_acc <> formatted, maybe_append(events_acc, raw)}
      end)

    {:noreply,
     %{
       state
       | logs: state.logs <> logs_append,
         line_buffer: remainder,
         raw_events: state.raw_events ++ new_raw_events
     }}
  end

  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    {logs_append, final_raw_events} = flush_line_buffer(state.line_buffer, state.provider)

    state = %{
      state
      | logs: state.logs <> logs_append,
        raw_events: state.raw_events ++ final_raw_events,
        line_buffer: ""
    }

    status = exit_status(state.stopping, code)
    Store.insert(state.id, {self(), state.command, status, state.started_at})
    {:stop, :normal, %{state | port: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    case Store.lookup(state.id) do
      {:exited, _, _, _} -> Store.persist_after_exit(state.id, state.logs, state.raw_events)
      _ -> :ok
    end
  end

  # Private helpers

  defp flush_line_buffer("", _provider), do: {"", []}

  defp flush_line_buffer(buffer, provider) do
    {event, raw} = provider.parse_line(buffer)
    formatted = provider.format_for_logs(event)
    {formatted, maybe_wrap(raw)}
  end

  defp maybe_append(list, nil), do: list
  defp maybe_append(list, event), do: list ++ [event]

  defp maybe_wrap(nil), do: []
  defp maybe_wrap(event), do: [event]

  defp exit_status(_stopping = true, _code), do: :stopped
  defp exit_status(_stopping, 0), do: :stopped
  defp exit_status(_stopping, _code), do: :crashed

  defp split_lines(data) do
    case String.split(data, "\n", parts: :infinity) do
      [] -> {[], ""}
      parts ->
        {lines, [remainder]} = Enum.split(parts, -1)
        {lines, remainder}
    end
  end
end
