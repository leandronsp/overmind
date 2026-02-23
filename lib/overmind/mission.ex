defmodule Overmind.Mission do
  @moduledoc false
  use GenServer

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
    case :ets.lookup(:overmind_missions, id) do
      [{^id, pid, _, :running, _}] ->
        try do
          {:ok, GenServer.call(pid, :get_logs)}
        catch
          :exit, _ -> {:error, :not_found}
        end

      [{^id, _, _, _status, _}] ->
        case :ets.lookup(:overmind_missions, {:logs, id}) do
          [{{:logs, ^id}, logs}] -> {:ok, logs}
          [] -> {:ok, ""}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @spec get_raw_events(String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def get_raw_events(id) do
    case :ets.lookup(:overmind_missions, id) do
      [{^id, pid, _, :running, _}] ->
        try do
          {:ok, GenServer.call(pid, :get_raw_events)}
        catch
          :exit, _ -> {:error, :not_found}
        end

      [{^id, _, _, _status, _}] ->
        case :ets.lookup(:overmind_missions, {:raw_events, id}) do
          [{{:raw_events, ^id}, events}] -> {:ok, events}
          [] -> {:ok, []}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @spec stop(String.t()) :: :ok | {:error, :not_found | :not_running}
  def stop(id) do
    case :ets.lookup(:overmind_missions, id) do
      [{^id, pid, _, :running, _}] ->
        try do
          GenServer.call(pid, {:stop, :sigterm})
        catch
          :exit, _ -> {:error, :not_running}
        end

      [{^id, _, _, _, _}] ->
        {:error, :not_running}

      [] ->
        {:error, :not_found}
    end
  end

  @spec kill(String.t()) :: :ok | {:error, :not_found}
  def kill(id) do
    case :ets.lookup(:overmind_missions, id) do
      [{^id, pid, _, :running, _}] ->
        try do
          GenServer.call(pid, {:kill, :sigkill})
        catch
          :exit, _ ->
            cleanup(id)
            :ok
        end

      [{^id, _, _, _, _}] ->
        cleanup(id)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  defp cleanup(id) do
    :ets.delete(:overmind_missions, id)
    :ets.delete(:overmind_missions, {:logs, id})
    :ets.delete(:overmind_missions, {:raw_events, id})
  end

  @spec get_info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_info(id) do
    case :ets.lookup(:overmind_missions, id) do
      [{^id, pid, command, status, started_at}] when status == :running ->
        os_pid = GenServer.call(pid, :get_os_pid)
        {:ok, %{id: id, command: command, status: status, started_at: started_at, os_pid: os_pid}}

      [{^id, _pid, command, status, started_at}] ->
        {:ok, %{id: id, command: command, status: status, started_at: started_at, os_pid: nil}}

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def init(%{id: id, command: command, provider: provider}) do
    port_command = provider.build_command(command) <> " < /dev/null"

    port =
      Port.open({:spawn, port_command}, [:binary, :exit_status, :stderr_to_stdout])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    now = System.system_time(:second)
    :ets.insert(:overmind_missions, {id, self(), command, :running, now})

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
    :ets.delete(:overmind_missions, state.id)
    :ets.delete(:overmind_missions, {:logs, state.id})
    :ets.delete(:overmind_missions, {:raw_events, state.id})
    {:stop, :normal, :ok, %{state | port: nil}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {lines, remainder} = split_lines(state.line_buffer <> data)

    {logs_append, new_raw_events} =
      Enum.reduce(lines, {"", []}, fn line, {logs_acc, events_acc} ->
        {event, raw} = state.provider.parse_line(line)
        formatted = state.provider.format_for_logs(event)
        events_acc = if raw, do: events_acc ++ [raw], else: events_acc
        {logs_acc <> formatted, events_acc}
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
    # Flush remaining line_buffer
    {logs_append, final_raw_events} =
      if state.line_buffer != "" do
        {event, raw} = state.provider.parse_line(state.line_buffer)
        formatted = state.provider.format_for_logs(event)
        events = if raw, do: [raw], else: []
        {formatted, events}
      else
        {"", []}
      end

    state = %{
      state
      | logs: state.logs <> logs_append,
        raw_events: state.raw_events ++ final_raw_events,
        line_buffer: ""
    }

    status =
      cond do
        state.stopping -> :stopped
        code == 0 -> :stopped
        true -> :crashed
      end

    :ets.insert(:overmind_missions, {state.id, self(), state.command, status, state.started_at})
    {:stop, :normal, %{state | port: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    case :ets.lookup(:overmind_missions, state.id) do
      [{_, _, _, status, _}] when status in [:stopped, :crashed] ->
        :ets.insert(:overmind_missions, {{:logs, state.id}, state.logs})
        :ets.insert(:overmind_missions, {{:raw_events, state.id}, state.raw_events})

      _ ->
        :ok
    end
  end

  defp split_lines(data) do
    case String.split(data, "\n", parts: :infinity) do
      [] -> {[], ""}
      parts ->
        {lines, [remainder]} = Enum.split(parts, -1)
        {lines, remainder}
    end
  end
end
