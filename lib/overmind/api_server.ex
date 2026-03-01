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

    case Overmind.run(command, opts) do
      {:ok, id} -> %{"ok" => id}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "ps"}) do
    missions = Overmind.ps()
    %{"ok" => Overmind.format_ps(missions)}
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

  def dispatch(%{"cmd" => "pause"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.pause(id) do
      {:ok, session_id} -> %{"ok" => session_id}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

  def dispatch(%{"cmd" => "unpause"} = req) do
    id = get_in(req, ["args", "id"])

    case Overmind.unpause(id) do
      :ok -> %{"ok" => true}
      {:error, reason} -> %{"error" => to_string(reason)}
    end
  end

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
end
