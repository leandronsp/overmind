defmodule Overmind.APIServer do
  @moduledoc false
  use GenServer

  @default_socket_path Path.expand("~/.overmind/overmind.sock")

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec dispatch(map()) :: map()
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
      |> maybe_add_restart(Map.get(args, "restart"))
      |> maybe_add_int(:max_restarts, Map.get(args, "max_restarts"))
      |> maybe_add_int(:max_seconds, Map.get(args, "max_seconds"))
      |> maybe_add_int(:backoff_ms, Map.get(args, "backoff"))
      |> maybe_add_int(:activity_timeout, Map.get(args, "activity_timeout"))
      |> maybe_add_parent(Map.get(args, "parent"))
      |> maybe_add_allowed_tools(Map.get(args, "allowed_tools"))

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

  def dispatch(%{"cmd" => "kill"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.kill(id) do
      :ok -> %{"ok" => true}
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

  # Returns missions as a JSON-safe list of maps (atoms converted to strings).
  # Used by the TUI to get structured data for navigation without parsing the
  # formatted table text returned by the regular "ps" command.
  def dispatch(%{"cmd" => "ps_json"}) do
    missions = Overmind.ps() |> Enum.map(&mission_to_json/1)
    %{"ok" => missions}
  end

  def dispatch(%{"cmd" => "top"}) do
    entries = Overmind.top()
    %{"ok" => Overmind.format_top(entries)}
  end

  def dispatch(%{"cmd" => "apply"} = req) do
    path = get_in(req, ["args", "path"])

    case Overmind.Blueprint.apply(path) do
      {:ok, results} -> %{"ok" => results}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "agents"} = req) do
    path = get_in(req, ["args", "path"])

    case Overmind.Blueprint.agents(path) do
      {:ok, specs} -> %{"ok" => Enum.map(specs, &agent_spec_to_json/1)}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "quest_run"} = req) do
    name = get_in(req, ["args", "name"]) || ""
    command = get_in(req, ["args", "command"]) || ""

    case Overmind.Quest.run(name, command) do
      {:ok, quest_id} -> %{"ok" => %{"id" => quest_id}}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "quest_list"}) do
    quests = Overmind.Quest.list() |> Enum.map(&quest_to_json/1)
    %{"ok" => quests}
  end

  def dispatch(%{"cmd" => "ritual_create"} = req) do
    name = get_in(req, ["args", "name"]) || ""
    cron = get_in(req, ["args", "cron"]) || ""
    command = get_in(req, ["args", "command"]) || ""

    case Overmind.Ritual.create(name, cron, command) do
      {:ok, id} -> %{"ok" => %{"id" => id}}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "ritual_list"}) do
    rituals = Overmind.Ritual.list() |> Enum.map(&ritual_to_json/1)
    %{"ok" => rituals}
  end

  def dispatch(%{"cmd" => "ritual_delete"} = req) do
    name = get_in(req, ["args", "name"]) || ""

    case Overmind.Ritual.delete(name) do
      :ok -> %{"ok" => true}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "isolate"} = req) do
    mission_id = get_in(req, ["args", "mission_id"])
    project_path = get_in(req, ["args", "project_path"])

    case Overmind.Isolation.setup(mission_id, project_path) do
      {:ok, result} ->
        env_map = Enum.into(result.env, %{})
        %{"ok" => %{"worktree_path" => result.worktree_path, "env" => env_map}}

      {:error, reason} ->
        %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "isolate_teardown"} = req) do
    mission_id = get_in(req, ["args", "mission_id"])
    project_path = get_in(req, ["args", "project_path"])
    Overmind.Isolation.teardown(mission_id, project_path)
    %{"ok" => true}
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
  defp handle_client(client) do
    case :gen_tcp.recv(client, 0, 5000) do
      {:ok, line} ->
        response =
          line
          |> String.trim()
          |> :json.decode()
          |> dispatch()
          |> :json.encode()
          |> IO.iodata_to_binary()

        :gen_tcp.send(client, response <> "\n")

      {:error, _} ->
        :ok
    end

    :gen_tcp.close(client)
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

  defp maybe_add_parent(opts, nil), do: opts
  defp maybe_add_parent(opts, parent), do: Keyword.put(opts, :parent, parent)

  defp maybe_add_allowed_tools(opts, nil), do: opts
  defp maybe_add_allowed_tools(opts, tools), do: Keyword.put(opts, :allowed_tools, tools)

  defp maybe_add_restart(opts, nil), do: opts
  defp maybe_add_restart(opts, str), do: Keyword.put(opts, :restart_policy, parse_restart(str))

  defp maybe_add_int(opts, _key, nil), do: opts
  defp maybe_add_int(opts, key, val) when is_integer(val), do: Keyword.put(opts, key, val)
  defp maybe_add_int(opts, key, val) when is_binary(val), do: Keyword.put(opts, key, String.to_integer(val))

  defp agent_spec_to_json(spec) do
    %{
      "name" => spec.name,
      "command" => spec.command,
      "provider" => provider_to_string(spec.provider),
      "type" => Atom.to_string(spec.type),
      "cwd" => nil_to_null(spec.cwd),
      "restart_policy" => Atom.to_string(spec.restart_policy),
      "depends_on" => spec.depends_on
    }
  end

  defp provider_to_string(Overmind.Provider.Claude), do: "claude"
  defp provider_to_string(_), do: "raw"

  defp parse_restart("on-failure"), do: :on_failure
  defp parse_restart("on_failure"), do: :on_failure
  defp parse_restart("always"), do: :always
  defp parse_restart("never"), do: :never
  defp parse_restart(_), do: :never

  # Converts a mission map (with atom values) to a JSON-safe map with string values.
  # Atom fields (status, type) must be stringified before :json.encode/1.
  defp mission_to_json(m) do
    %{
      "id" => m.id,
      "name" => m[:name] || "",
      "command" => m.command,
      "status" => Atom.to_string(m.status),
      "type" => Atom.to_string(m.type),
      "restart_count" => m[:restart_count] || 0,
      "uptime" => m.uptime,
      "parent" => nil_to_null(m[:parent]),
      "children" => m[:children] || 0
    }
  end

  defp quest_to_json(q) do
    %{
      "id" => q.id,
      "name" => q.name,
      "command" => q.command,
      "status" => Atom.to_string(q.status),
      "mission_id" => nil_to_null(q.mission_id),
      "created_at" => q.created_at
    }
  end

  defp ritual_to_json(r) do
    %{
      "id" => r.id,
      "name" => r.name,
      "cron_expr" => r.cron_expr,
      "command" => r.command,
      "created_at" => r.created_at,
      "last_run_at" => nil_to_null(r.last_run_at)
    }
  end
end
