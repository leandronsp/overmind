defmodule Overmind.Session do
  @moduledoc false
  use GenServer

  defstruct [:id, :command, :port, :os_pid, :started_at, logs: ""]

  @type t :: %__MODULE__{
          id: String.t(),
          command: String.t(),
          port: port() | nil,
          os_pid: non_neg_integer(),
          started_at: integer(),
          logs: String.t()
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
    GenServer.start_link(__MODULE__, %{id: id, command: command})
  end

  @spec get_logs(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_logs(id) do
    case :ets.lookup(:overmind_sessions, id) do
      [{^id, pid, _, :running, _}] ->
        try do
          {:ok, GenServer.call(pid, :get_logs)}
        catch
          :exit, _ -> {:error, :not_found}
        end

      [{^id, _, _, _status, _}] ->
        case :ets.lookup(:overmind_sessions, {:logs, id}) do
          [{{:logs, ^id}, logs}] -> {:ok, logs}
          [] -> {:ok, ""}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @spec signal(String.t(), :sigterm | :sigkill) :: :ok | {:error, :not_found | :not_running}
  def signal(id, sig) do
    case :ets.lookup(:overmind_sessions, id) do
      [{^id, pid, _, :running, _}] ->
        try do
          GenServer.call(pid, {:signal, sig})
        catch
          :exit, _ -> {:error, :not_running}
        end

      [{^id, _, _, _, _}] ->
        {:error, :not_running}

      [] ->
        {:error, :not_found}
    end
  end

  @spec get_info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_info(id) do
    case :ets.lookup(:overmind_sessions, id) do
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
  def init(%{id: id, command: command}) do
    port =
      Port.open({:spawn, command}, [:binary, :exit_status, :stderr_to_stdout])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    now = System.system_time(:second)
    :ets.insert(:overmind_sessions, {id, self(), command, :running, now})

    {:ok,
     %__MODULE__{
       id: id,
       command: command,
       port: port,
       os_pid: os_pid,
       started_at: now
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
  def handle_call({:signal, sig}, _from, state) do
    flag = if sig == :sigkill, do: "-9", else: "-15"
    os_pid_str = Integer.to_string(state.os_pid)
    System.cmd("kill", [flag, os_pid_str])
    :ets.delete(:overmind_sessions, state.id)
    :ets.delete(:overmind_sessions, {:logs, state.id})
    {:stop, :normal, :ok, %{state | port: nil}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {:noreply, %{state | logs: state.logs <> data}}
  end

  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    status = if code == 0, do: :stopped, else: :crashed
    :ets.insert(:overmind_sessions, {state.id, self(), state.command, status, state.started_at})
    {:stop, :normal, %{state | port: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    case :ets.lookup(:overmind_sessions, state.id) do
      [{_, _, _, status, _}] when status in [:stopped, :crashed] ->
        :ets.insert(:overmind_sessions, {{:logs, state.id}, state.logs})

      _ ->
        :ok
    end
  end
end
