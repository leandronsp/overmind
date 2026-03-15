defmodule Overmind.Blueprint.Runner do
  @moduledoc false
  use GenServer

  alias Overmind.Mission.Store

  defstruct [
    :id,
    :command,
    :started_at,
    :worker,
    logs: "",
    stopping: false
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          command: String.t(),
          started_at: integer(),
          worker: pid() | nil,
          logs: String.t(),
          stopping: boolean()
        }

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
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    filename = Keyword.fetch!(opts, :filename)
    specs = Keyword.fetch!(opts, :specs)

    Process.flag(:trap_exit, true)

    now = System.system_time(:second)
    command = "blueprint: #{filename}"
    Store.insert(id, {self(), command, :running, now})
    Store.insert_type(id, :blueprint)
    Store.insert_name(id, name)

    runner = self()
    worker = spawn_link(fn -> run_pipeline(runner, specs) end)

    {:ok,
     %__MODULE__{
       id: id,
       command: command,
       started_at: now,
       worker: worker
     }}
  end

  @impl true
  def handle_call(:get_logs, _from, state) do
    {:reply, state.logs, state}
  end

  @impl true
  def handle_call({:stop, :sigterm}, _from, state) do
    kill_worker(state.worker)
    Store.insert(state.id, {self(), state.command, :stopped, state.started_at})
    Store.insert_exit_code(state.id, 0)
    {:stop, :normal, :ok, %{state | stopping: true, worker: nil}}
  end

  @impl true
  def handle_call({:kill, :sigkill}, _from, state) do
    kill_worker(state.worker)
    Store.cleanup(state.id)
    {:stop, :normal, :ok, %{state | worker: nil}}
  end

  @impl true
  def handle_info({:pipeline_log, line}, state) do
    {:noreply, %{state | logs: state.logs <> line <> "\n"}}
  end

  @impl true
  def handle_info({:pipeline_done, :ok}, state) do
    Store.insert(state.id, {self(), state.command, :stopped, state.started_at})
    Store.insert_exit_code(state.id, 0)
    {:stop, :normal, %{state | worker: nil}}
  end

  @impl true
  def handle_info({:pipeline_done, {:error, agent_name}}, state) do
    state = %{state | logs: state.logs <> "pipeline failed at agent '#{agent_name}'\n", worker: nil}
    Store.insert(state.id, {self(), state.command, :crashed, state.started_at})
    Store.insert_exit_code(state.id, 1)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, pid, _reason}, %{worker: pid} = state) do
    # Worker crashed unexpectedly
    state = %{state | worker: nil}

    unless state.stopping do
      Store.insert(state.id, {self(), state.command, :crashed, state.started_at})
      Store.insert_exit_code(state.id, 1)
    end

    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    case Store.lookup(state.id) do
      :not_found -> :ok
      _ -> Store.persist_after_exit(state.id, state.logs, [])
    end
  end

  # Worker pipeline logic — runs in a separate process so the GenServer
  # stays responsive for get_logs, stop, kill.

  defp run_pipeline(runner, specs) do
    run_pipeline(runner, specs, [])
  end

  defp run_pipeline(runner, [], _completed) do
    Kernel.send(runner, {:pipeline_done, :ok})
  end

  defp run_pipeline(runner, [spec | rest], completed) do
    opts = build_opts(spec, completed)

    case Overmind.run(spec.command, opts) do
      {:ok, id} ->
        Kernel.send(runner, {:pipeline_log, "started #{spec.name} (#{id})"})
        {:ok, wait_result} = Overmind.wait(id)

        case wait_result.status do
          :stopped ->
            Kernel.send(runner, {:pipeline_log, "#{spec.name} stopped"})
            run_pipeline(runner, rest, [{spec.name, id} | completed])

          _ ->
            Kernel.send(runner, {:pipeline_log, "#{spec.name} #{wait_result.status}"})
            Kernel.send(runner, {:pipeline_done, {:error, spec.name}})
        end

      {:error, reason} ->
        Kernel.send(runner, {:pipeline_log, "failed to start #{spec.name}: #{reason}"})
        Kernel.send(runner, {:pipeline_done, {:error, spec.name}})
    end
  end

  defp build_opts(spec, completed) do
    [provider: spec.provider, type: spec.type, name: spec.name, restart_policy: spec.restart_policy]
    |> maybe_add(:cwd, spec.cwd)
    |> maybe_add_parent(spec.depends_on, completed)
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, val), do: Keyword.put(opts, key, val)

  defp maybe_add_parent(opts, [], _completed), do: opts

  defp maybe_add_parent(opts, [first_dep | _], completed) do
    case List.keyfind(completed, first_dep, 0) do
      {_, parent_id} -> Keyword.put(opts, :parent, parent_id)
      nil -> opts
    end
  end

  defp kill_worker(nil), do: :ok
  defp kill_worker(pid), do: Process.exit(pid, :kill)
end
