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

    case Overmind.run(command, opts) do
      {:ok, id} -> %{"ok" => id}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "ps"}) do
    missions = Overmind.ps()
    %{"ok" => Overmind.format_ps(missions)}
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

  def dispatch(%{"cmd" => "stop"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.stop(id) do
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
        %{"ok" => %{"session_id" => session_id, "cwd" => cwd}}

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
end
