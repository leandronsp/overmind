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
    :session_id,
    :cwd,
    :name,
    :restart_timer_ref,
    :last_activity_at,
    :activity_timer_ref,
    type: :task,
    logs: "",
    line_buffer: "",
    raw_events: [],
    stopping: false,
    paused: false,
    restart_policy: :never,
    max_restarts: 5,
    max_seconds: 60,
    backoff_ms: 1000,
    restart_count: 0,
    restart_timestamps: [],
    activity_timeout: 0
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          command: String.t(),
          port: port() | nil,
          os_pid: non_neg_integer() | nil,
          started_at: integer(),
          provider: module(),
          session_id: String.t() | nil,
          cwd: String.t() | nil,
          name: String.t(),
          type: :task | :session,
          logs: String.t(),
          line_buffer: String.t(),
          raw_events: [map()],
          stopping: boolean(),
          paused: boolean(),
          restart_policy: :never | :on_failure | :always,
          max_restarts: non_neg_integer(),
          max_seconds: non_neg_integer(),
          backoff_ms: non_neg_integer(),
          restart_count: non_neg_integer(),
          restart_timestamps: [integer()],
          restart_timer_ref: reference() | nil,
          activity_timeout: non_neg_integer(),
          last_activity_at: integer() | nil,
          activity_timer_ref: reference() | nil
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
    type = Keyword.get(opts, :type, :task)
    cwd = Keyword.get(opts, :cwd)
    name = Keyword.get(opts, :name) || Overmind.Mission.Name.generate()
    restart_policy = Keyword.get(opts, :restart_policy, :never)
    max_restarts = Keyword.get(opts, :max_restarts, 5)
    max_seconds = Keyword.get(opts, :max_seconds, 60)
    backoff_ms = Keyword.get(opts, :backoff_ms, 1000)
    activity_timeout = Keyword.get(opts, :activity_timeout, 0)

    GenServer.start_link(__MODULE__, %{
      id: id,
      command: command,
      provider: provider,
      type: type,
      cwd: cwd,
      name: name,
      restart_policy: restart_policy,
      max_restarts: max_restarts,
      max_seconds: max_seconds,
      backoff_ms: backoff_ms,
      activity_timeout: activity_timeout
    })
  end

  # GenServer callbacks

  # Port is opened eagerly in init — the mission is visible in ETS (via ps)
  # immediately, before start_link returns to the caller.
  @impl true
  def init(%{id: id, command: command, provider: provider, type: type, cwd: cwd, name: name} = args) do
    restart_policy = Map.get(args, :restart_policy, :never)
    max_restarts = Map.get(args, :max_restarts, 5)
    max_seconds = Map.get(args, :max_seconds, 60)
    backoff_ms = Map.get(args, :backoff_ms, 1000)
    activity_timeout = Map.get(args, :activity_timeout, 0)

    port_command = build_port_command(type, provider, command)
    port_opts = [:binary, :exit_status, :stderr_to_stdout] ++ clean_env() ++ maybe_cd(cwd)
    port = Port.open({:spawn, port_command}, port_opts)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    now = System.system_time(:second)
    Store.insert(id, {self(), command, :running, now})
    Store.insert_type(id, type)
    Store.insert_name(id, name)
    Store.insert_restart_policy(id, restart_policy)
    maybe_store_cwd(id, cwd)
    send_initial_prompt(type, port, provider, command)

    activity_timer_ref = schedule_activity_check(activity_timeout)
    last_activity_at = if activity_timeout > 0, do: now, else: nil

    {:ok,
     %__MODULE__{
       id: id,
       command: command,
       port: port,
       os_pid: os_pid,
       started_at: now,
       provider: provider,
       type: type,
       cwd: cwd,
       name: name,
       restart_policy: restart_policy,
       max_restarts: max_restarts,
       max_seconds: max_seconds,
       backoff_ms: backoff_ms,
       activity_timeout: activity_timeout,
       last_activity_at: last_activity_at,
       activity_timer_ref: activity_timer_ref
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
  def handle_call(:pause, _from, state) do
    Store.insert_attached(state.id, true)
    {:reply, state.session_id, %{state | paused: true}}
  end

  @impl true
  def handle_call(:unpause, _from, state) do
    Store.insert_attached(state.id, false)
    {:reply, :ok, %{state | paused: false}}
  end

  @impl true
  def handle_call({:stop, :sigterm}, _from, %{port: nil} = state) do
    cancel_timer(state.restart_timer_ref)
    Store.insert(state.id, {self(), state.command, :stopped, state.started_at})
    {:stop, :normal, :ok, %{state | restart_timer_ref: nil, stopping: true}}
  end

  @impl true
  def handle_call({:stop, :sigterm}, _from, state) do
    System.cmd("kill", ["-15", Integer.to_string(state.os_pid)])
    {:reply, :ok, %{state | stopping: true}}
  end

  @impl true
  def handle_call({:kill, :sigkill}, _from, %{port: nil} = state) do
    cancel_timer(state.restart_timer_ref)
    Store.cleanup(state.id)
    {:stop, :normal, :ok, %{state | restart_timer_ref: nil}}
  end

  @impl true
  def handle_call({:kill, :sigkill}, _from, state) do
    System.cmd("kill", ["-9", Integer.to_string(state.os_pid)])
    Store.cleanup(state.id)
    {:stop, :normal, :ok, %{state | port: nil}}
  end

  @impl true
  def handle_cast({:send, message}, state) do
    data = state.provider.build_input_message(message)
    Port.command(state.port, data)
    {:noreply, %{state | logs: state.logs <> "[human] #{message}\n"}}
  end

  # Port data arrives as arbitrary byte chunks — we buffer partial lines and
  # only process complete newline-terminated lines through the provider.
  # Each line is parsed into a structured event, formatted for human-readable
  # logs, and optionally stored as a raw JSON event (for claude provider).
  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {lines, remainder} = split_lines(state.line_buffer <> data)

    {logs_append, new_raw_events, session_id} =
      Enum.reduce(lines, {"", [], state.session_id}, fn line, {logs_acc, events_acc, sid} ->
        {event, raw} = state.provider.parse_line(line)
        formatted = state.provider.format_for_logs(event)
        new_sid = extract_session_id(event, sid)
        {logs_acc <> formatted, maybe_append(events_acc, raw), new_sid}
      end)

    maybe_store_session_id(session_id, state)
    now = System.system_time(:second)
    maybe_update_activity(state.activity_timeout, state.id, now)

    {:noreply,
     %{
       state
       | logs: state.logs <> logs_append,
         line_buffer: remainder,
         raw_events: state.raw_events ++ new_raw_events,
         session_id: session_id,
         last_activity_at: update_last_activity(state.activity_timeout, state.last_activity_at, now)
     }}
  end

  # Port exit: flush remaining buffer, decide whether to restart or terminate.
  # Restart decision follows the policy chain: stopping? → policy → budget check.
  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    {logs_append, final_raw_events} = flush_line_buffer(state.line_buffer, state.provider)

    state = %{
      state
      | logs: state.logs <> logs_append,
        raw_events: state.raw_events ++ final_raw_events,
        line_buffer: "",
        port: nil,
        os_pid: nil
    }

    cancel_timer(state.activity_timer_ref)
    status = exit_status(state.stopping, code)

    case should_restart?(state, status) do
      true ->
        delay = compute_backoff(state)
        timer_ref = Process.send_after(self(), :restart, delay)
        Store.insert(state.id, {self(), state.command, :restarting, state.started_at})
        {:noreply, %{state | restart_timer_ref: timer_ref, activity_timer_ref: nil}}

      false ->
        Store.insert(state.id, {self(), state.command, status, state.started_at})
        {:stop, :normal, state}
    end
  end

  # Stall detection: periodic timer fires to check if the process has produced
  # output recently. SIGKILL bypasses graceful shutdown — the port exit_status
  # handler then decides whether to restart based on the restart policy.
  @impl true
  def handle_info(:check_activity, %{port: nil} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_activity, state) do
    now = System.system_time(:second)
    elapsed = now - (state.last_activity_at || now)

    case elapsed >= state.activity_timeout do
      true ->
        System.cmd("kill", ["-9", Integer.to_string(state.os_pid)])
        marker = "--- killed: no activity for #{elapsed}s ---\n"
        {:noreply, %{state | logs: state.logs <> marker, activity_timer_ref: nil}}

      false ->
        ref = schedule_activity_check(state.activity_timeout)
        {:noreply, %{state | activity_timer_ref: ref}}
    end
  end

  # Re-open the Port with the same command. For sessions, passes session_id
  # so claude --resume picks up where it left off. Logs/raw_events accumulate
  # across restarts (never reset). Attached/paused state is cleared.
  @impl true
  def handle_info(:restart, state) do
    count = state.restart_count + 1
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%dT%H:%M:%SZ")
    marker = "--- restart ##{count} at #{timestamp} ---\n"
    now_mono = System.monotonic_time(:millisecond)

    port_command = build_port_command(state.type, state.provider, state.command, state.session_id)
    port_opts = [:binary, :exit_status, :stderr_to_stdout] ++ clean_env() ++ maybe_cd(state.cwd)
    port = Port.open({:spawn, port_command}, port_opts)
    {:os_pid, os_pid} = Port.info(port, :os_pid)

    Store.insert(state.id, {self(), state.command, :running, state.started_at})
    Store.insert_restart_count(state.id, count)
    Store.insert_attached(state.id, false)

    now = System.system_time(:second)
    activity_timer_ref = schedule_activity_check(state.activity_timeout)
    last_activity_at = if state.activity_timeout > 0, do: now, else: nil

    {:noreply,
     %{
       state
       | port: port,
         os_pid: os_pid,
         logs: state.logs <> marker,
         restart_count: count,
         restart_timestamps: state.restart_timestamps ++ [now_mono],
         restart_timer_ref: nil,
         stopping: false,
         paused: false,
         activity_timer_ref: activity_timer_ref,
         last_activity_at: last_activity_at
     }}
  end

  @impl true
  def terminate(_reason, state) do
    Store.persist_after_exit(state.id, state.logs, state.raw_events)
  end

  # --- Private helpers ---

  # Flush any remaining partial line when the port exits
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

  defp extract_session_id({:system, %{"subtype" => "init", "session_id" => sid}}, _old), do: sid
  defp extract_session_id(_, old), do: old

  defp maybe_store_session_id(nil, _state), do: :ok
  defp maybe_store_session_id(sid, %{session_id: sid}), do: :ok
  defp maybe_store_session_id(sid, state), do: Store.insert_session_id(state.id, sid)

  defp maybe_cd(nil), do: []
  defp maybe_cd(cwd), do: [{:cd, String.to_charlist(cwd)}]

  # Allow spawning Claude CLI as a subprocess inside a Claude Code session.
  # These env vars trigger nesting detection — unsetting them lets the child
  # process run as a standalone instance.
  defp clean_env do
    [{:env, [{~c"CLAUDECODE", false}, {~c"CLAUDE_CODE_ENTRYPOINT", false}]}]
  end

  defp maybe_store_cwd(_id, nil), do: :ok
  defp maybe_store_cwd(id, cwd), do: Store.insert_cwd(id, cwd)

  defp send_initial_prompt(:session, port, provider, command) when command != "" do
    Port.command(port, provider.build_input_message(command))
  end

  defp send_initial_prompt(_, _, _, _), do: :ok

  defp build_port_command(type, provider, command) do
    build_port_command(type, provider, command, nil)
  end

  defp build_port_command(:session, provider, _command, session_id) do
    provider.build_session_command(session_id: session_id)
  end

  defp build_port_command(:task, provider, command, _session_id) do
    provider.build_command(command) <> " < /dev/null"
  end

  # Restart policy dispatch: manual stop always wins, then policy, then budget.
  # :on_failure only restarts on non-zero exit; :always restarts unconditionally.
  defp should_restart?(%{stopping: true}, _status), do: false
  defp should_restart?(%{restart_policy: :never}, _status), do: false
  defp should_restart?(%{restart_policy: :on_failure}, :stopped), do: false

  defp should_restart?(%{restart_policy: policy} = state, _status)
       when policy in [:on_failure, :always],
       do: within_restart_budget?(state)

  # Sliding window budget: count restarts within the last max_seconds.
  # max_restarts=0 means unlimited restarts.
  defp within_restart_budget?(%{max_restarts: 0}), do: true

  defp within_restart_budget?(%{max_restarts: max, max_seconds: window, restart_timestamps: timestamps}) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - window * 1000
    recent = Enum.count(timestamps, fn t -> t >= cutoff end)
    recent < max
  end

  # Exponential backoff: base × 2^count, capped at 60s
  defp compute_backoff(%{backoff_ms: base, restart_count: count}) do
    delay = base * Integer.pow(2, count)
    min(delay, 60_000)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp maybe_update_activity(0, _id, _now), do: :ok
  defp maybe_update_activity(_timeout, id, now), do: Store.insert_last_activity(id, now)

  defp update_last_activity(0, old, _now), do: old
  defp update_last_activity(_timeout, _old, now), do: now

  defp schedule_activity_check(0), do: nil

  defp schedule_activity_check(timeout_s) do
    Process.send_after(self(), :check_activity, timeout_s * 1000)
  end

  # Split on newlines, keeping the last (possibly incomplete) chunk as the
  # line buffer. Complete lines are returned for processing; the remainder
  # waits for more data or gets flushed on port exit.
  defp split_lines(data) do
    case String.split(data, "\n", parts: :infinity) do
      [] -> {[], ""}
      parts ->
        {lines, [remainder]} = Enum.split(parts, -1)
        {lines, remainder}
    end
  end
end
