defmodule Overmind.APIServer do
  @moduledoc false
  use GenServer

  @default_socket_path Path.expand("~/.overmind/overmind.sock")

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec dispatch(map()) :: map() | {:stream, String.t()}
  def dispatch(%{"cmd" => "run"} = req) do
    args = Map.get(req, "args", %{})
    command = Map.get(args, "command", "")
    type = parse_type(Map.get(args, "type", "task"))
    provider = parse_provider(Map.get(args, "provider", "raw"))
    cwd = Map.get(args, "cwd")
    name = Map.get(args, "name")

    opts =
      [type: type, provider: provider]
      |> maybe_add_cwd(cwd)
      |> maybe_add_name(name)
      |> maybe_add_model(Map.get(args, "model"))
      |> maybe_add_restart(Map.get(args, "restart"))
      |> maybe_add_int(:max_restarts, Map.get(args, "max_restarts"))
      |> maybe_add_int(:max_seconds, Map.get(args, "max_seconds"))
      |> maybe_add_int(:backoff_ms, Map.get(args, "backoff"))
      |> maybe_add_int(:activity_timeout, Map.get(args, "activity_timeout"))
      |> maybe_add_parent(Map.get(args, "parent"))

    case Overmind.run(command, opts) do
      {:ok, id} ->
        name = Overmind.Mission.Store.lookup_name(id)
        %{"ok" => %{"id" => id, "name" => name}}

      {:error, reason} ->
        %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "ps", "args" => %{"tree" => true}}) do
    missions = Overmind.ps()
    %{"ok" => Overmind.format_ps_tree(missions)}
  end

  def dispatch(%{"cmd" => "ps", "args" => %{"children" => id}}) do
    missions = Overmind.children(id)
    %{"ok" => Overmind.format_ps(missions)}
  end

  def dispatch(%{"cmd" => "ps"}) do
    missions = Overmind.ps()
    %{"ok" => Overmind.format_ps(missions)}
  end

  def dispatch(%{"cmd" => "wait"} = req) do
    id = get_in(req, ["args", "id"])
    timeout = get_in(req, ["args", "timeout"])

    case Overmind.wait(id, timeout) do
      {:ok, result} ->
        %{"ok" => %{"status" => to_string(result.status), "exit_code" => nil_to_null(result.exit_code)}}

      {:error, reason} ->
        %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "info"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.info(id) do
      {:ok, info} -> %{"ok" => info}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "logs", "args" => %{"all" => true}}) do
    {:ok, logs} = Overmind.logs_all()
    %{"ok" => logs}
  end

  def dispatch(%{"cmd" => "logs"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.logs(id) do
      {:ok, logs} -> %{"ok" => logs}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "result"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.result(id) do
      {:ok, result} -> %{"ok" => result}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "stop"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.stop(id) do
      :ok -> %{"ok" => true}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "kill", "args" => %{"cascade" => true, "id" => id}}) do
    case Overmind.kill_cascade(id) do
      :ok -> %{"ok" => true}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "kill", "args" => %{"all" => true}}) do
    Overmind.kill_all()
    %{"ok" => true}
  end

  def dispatch(%{"cmd" => "kill"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.kill(id) do
      :ok -> %{"ok" => true}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "send", "args" => %{"wait" => true}} = req) do
    id = get_in(req, ["args", "id"])
    message = get_in(req, ["args", "message"])
    timeout = get_in(req, ["args", "timeout"]) || 60_000

    case Overmind.send_and_wait(id, message, timeout) do
      {:ok, result} -> %{"ok" => format_result(result)}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "send"} = req) do
    id = get_in(req, ["args", "id"])
    message = get_in(req, ["args", "message"])

    case Overmind.send(id, message) do
      :ok -> %{"ok" => true}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  # CWD is fetched separately because the CLI needs it to `cd` before
  # running `claude --resume` (session state lives in the mission's CWD).
  def dispatch(%{"cmd" => "pause"} = req) do
    id = get_in(req, ["args", "id"])
    resolved = Overmind.Mission.Store.resolve_id(id)

    case Overmind.pause(id) do
      {:ok, session_id} ->
        cwd = Overmind.Mission.Store.lookup_cwd(resolved)
        %{"ok" => %{"session_id" => nil_to_null(session_id), "cwd" => nil_to_null(cwd)}}

      {:error, reason} ->
        %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "unpause"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.unpause(id) do
      :ok -> %{"ok" => true}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "agents"} = req) do
    path = get_in(req, ["args", "path"])

    case Overmind.Blueprint.agents(path) do
      {:ok, specs} ->
        %{"ok" => Enum.map(specs, &format_agent_spec/1)}

      {:error, reason} ->
        %{"error" => format_blueprint_error(reason)}
    end
  end

  def dispatch(%{"cmd" => "apply"} = req) do
    path = get_in(req, ["args", "path"])

    case Overmind.Blueprint.apply(path) do
      {:ok, %{id: id, name: name}} ->
        %{"ok" => %{"id" => id, "name" => name}}

      {:error, reason} ->
        %{"error" => format_blueprint_error(reason)}
    end
  end

  def dispatch(%{"cmd" => "status"}) do
    %{"ok" => Overmind.status()}
  end

  # Async shutdown: spawn with delay so the JSON response reaches the client
  # before :init.stop() tears down the VM and closes the socket.
  def dispatch(%{"cmd" => "shutdown"}) do
    spawn(fn ->
      Process.sleep(100)
      :init.stop()
    end)

    %{"ok" => true}
  end

  def dispatch(%{"cmd" => "subscribe"} = req) do
    id = get_in(req, ["args", "id"])
    resolved = Overmind.Mission.Store.resolve_id(id)

    case Overmind.Mission.Store.lookup(resolved) do
      :not_found -> %{"error" => "not_found"}
      _ -> {:stream, resolved}
    end
  end

  def dispatch(%{"cmd" => cmd}) do
    %{"error" => "unknown command: #{cmd}"}
  end

  def dispatch(_) do
    %{"error" => "invalid request"}
  end

  # GenServer callbacks

  # Unix domain socket via :gen_tcp with {:ifaddr, {:local, path}}.
  # Port 0 is required by :gen_tcp but ignored for Unix sockets.
  # Protocol: newline-delimited JSON (one request, one response per connection).
  @impl true
  def init(opts) do
    path = Keyword.get(opts, :socket_path, @default_socket_path)
    File.mkdir_p!(Path.dirname(path))
    File.rm(path)

    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        {:ifaddr, {:local, path}},
        {:packet, :line},
        {:active, false},
        {:reuseaddr, true}
      ])

    acceptor = spawn(fn -> accept_loop(listen) end)
    {:ok, %{listen: listen, path: path, acceptor: acceptor}}
  end

  @impl true
  def terminate(_reason, state) do
    Process.exit(state.acceptor, :kill)
    :gen_tcp.close(state.listen)
    File.rm(state.path)
  end

  # Private

  defp accept_loop(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, client} ->
        spawn(fn -> handle_client(client) end)
        accept_loop(listen)

      {:error, :closed} ->
        :ok
    end
  end

  # One request per connection: read JSON line, dispatch, respond, close.
  # 5s timeout guards against hung clients holding the socket.
  # Subscribe commands enter a streaming loop instead of the normal path.
  defp handle_client(client) do
    case :gen_tcp.recv(client, 0, 5000) do
      {:ok, line} ->
        case line |> String.trim() |> :json.decode() |> dispatch() do
          {:stream, mission_id} ->
            stream_events(client, mission_id)

          response ->
            encoded = response |> :json.encode() |> IO.iodata_to_binary()
            :gen_tcp.send(client, encoded <> "\n")
        end

      {:error, _} ->
        :ok
    end

    :gen_tcp.close(client)
  end

  # Subscribe to mission events and write NDJSON lines until mission exits
  # or the client disconnects.
  defp stream_events(client, mission_id) do
    Overmind.PubSub.subscribe(mission_id)
    stream_loop(client, mission_id)
  end

  defp stream_loop(client, mission_id) do
    receive do
      {:mission_event, ^mission_id, event, raw} ->
        line = format_stream_event(event, raw)
        case :gen_tcp.send(client, line <> "\n") do
          :ok -> stream_loop(client, mission_id)
          {:error, _} -> :ok
        end

      {:mission_exit, ^mission_id, status, exit_code} ->
        line = :json.encode(%{"type" => "exit", "status" => to_string(status), "exit_code" => nil_to_null(exit_code)})
               |> IO.iodata_to_binary()
        :gen_tcp.send(client, line <> "\n")
    end
  end

  defp format_stream_event({type, _content}, raw) when type in [:text, :tool_use, :thinking, :result, :system, :tool_result] do
    :json.encode(raw) |> IO.iodata_to_binary()
  end

  defp format_stream_event({:plain, text}, _raw) do
    :json.encode(%{"type" => "plain", "text" => text}) |> IO.iodata_to_binary()
  end

  defp format_stream_event({:ignored, _}, raw) do
    :json.encode(raw) |> IO.iodata_to_binary()
  end

  defp parse_type("session"), do: :session
  defp parse_type(_), do: :task

  defp parse_provider("claude"), do: Overmind.Provider.Claude
  defp parse_provider(_), do: Overmind.Provider.Raw

  defp maybe_add_cwd(opts, nil), do: opts
  defp maybe_add_cwd(opts, cwd), do: Keyword.put(opts, :cwd, cwd)

  defp maybe_add_name(opts, nil), do: opts
  defp maybe_add_name(opts, name), do: Keyword.put(opts, :name, name)

  # Elixir's :json encodes nil as "nil" (string), not JSON null.
  # Use :null atom to get proper JSON null output.
  defp nil_to_null(nil), do: :null
  defp nil_to_null(val), do: val

  defp maybe_add_model(opts, nil), do: opts
  defp maybe_add_model(opts, model), do: Keyword.put(opts, :model, model)

  defp maybe_add_parent(opts, nil), do: opts
  defp maybe_add_parent(opts, parent), do: Keyword.put(opts, :parent, parent)

  defp maybe_add_restart(opts, nil), do: opts
  defp maybe_add_restart(opts, str), do: Keyword.put(opts, :restart_policy, parse_restart(str))

  defp maybe_add_int(opts, _key, nil), do: opts
  defp maybe_add_int(opts, key, val) when is_integer(val), do: Keyword.put(opts, key, val)
  defp maybe_add_int(opts, key, val) when is_binary(val), do: Keyword.put(opts, key, String.to_integer(val))

  defp parse_restart("on-failure"), do: :on_failure
  defp parse_restart("on_failure"), do: :on_failure
  defp parse_restart("always"), do: :always
  defp parse_restart("never"), do: :never
  defp parse_restart(_), do: :never

  defp format_agent_spec(spec) do
    base = %{"name" => spec.name, "command" => spec.command, "depends_on" => spec.depends_on}
    maybe_add_to_map(base, "model", spec.model)
  end

  defp maybe_add_to_map(map, _key, nil), do: map
  defp maybe_add_to_map(map, key, val), do: Map.put(map, key, val)

  defp format_result(result) do
    %{
      "text" => result.text,
      "duration_ms" => result.duration_ms,
      "cost_usd" => result.cost_usd
    }
  end

  defp format_blueprint_error({:missing_command, name}), do: "missing command for agent: #{name}"
  defp format_blueprint_error({:unknown_dependency, name, dep}), do: "agent #{name} depends on unknown agent: #{dep}"
  defp format_blueprint_error({:invalid_toml, _}), do: "invalid TOML"
  defp format_blueprint_error(reason), do: to_string(reason)
end
