defmodule Overmind.TUI.App do
  @moduledoc false
  use GenServer

  alias Overmind.TUI.Keybindings
  alias Overmind.TUI.Panels.Logs
  alias Overmind.TUI.Panels.Missions

  @refresh_ms 2000

  defstruct [
    panel: :missions,
    missions: [],
    selected: 0,
    logs: "",
    selected_id: nil,
    width: 80,
    height: 24,
    error: nil
  ]

  @type t :: %__MODULE__{
          panel: :missions | :logs | :help,
          missions: [map()],
          selected: non_neg_integer(),
          logs: String.t(),
          selected_id: String.t() | nil,
          width: non_neg_integer(),
          height: non_neg_integer(),
          error: String.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    {height, width} = terminal_size()
    state = struct!(__MODULE__, width: width, height: height)
    state = load_missions(state)
    :timer.send_interval(@refresh_ms, :refresh)

    # Spawn stdin reader unless told to skip (used in tests)
    skip_stdin = Keyword.get(opts, :skip_stdin, false)
    maybe_start_reader(self(), skip_stdin)

    render(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    state = load_missions(state)
    render(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:key, key}, state) do
    case Keybindings.handle(key) do
      :quit -> {:stop, :normal, state}
      action -> apply_action(action, state)
    end
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  # Private — key action dispatch

  defp apply_action(:nav_down, %{missions: []} = state), do: {:noreply, state}

  defp apply_action(:nav_down, state) do
    sel = min(state.selected + 1, length(state.missions) - 1)
    state = %{state | selected: sel}
    render(state)
    {:noreply, state}
  end

  defp apply_action(:nav_up, state) do
    sel = max(state.selected - 1, 0)
    state = %{state | selected: sel}
    render(state)
    {:noreply, state}
  end

  defp apply_action(:show_logs, %{missions: []} = state), do: {:noreply, state}

  defp apply_action(:show_logs, state) do
    mission = Enum.at(state.missions, state.selected)
    id = mission["id"]
    logs = fetch_logs(id)
    state = %{state | panel: :logs, logs: logs, selected_id: id}
    render(state)
    {:noreply, state}
  end

  defp apply_action(:show_missions, state) do
    state = %{state | panel: :missions}
    render(state)
    {:noreply, state}
  end

  defp apply_action(:show_help, state) do
    state = %{state | panel: :help}
    render(state)
    {:noreply, state}
  end

  defp apply_action(:refresh, state) do
    state = load_missions(state)
    render(state)
    {:noreply, state}
  end

  defp apply_action(:unknown, state), do: {:noreply, state}

  # Private — data loading

  defp load_missions(state) do
    case fetch_missions() do
      {:ok, missions} -> %{state | missions: missions, error: nil}
      {:error, reason} -> %{state | error: to_string(reason)}
    end
  end

  defp fetch_missions do
    case send_to_daemon(~s({"cmd":"ps_json"})) do
      {:ok, %{"ok" => missions}} when is_list(missions) -> {:ok, missions}
      {:ok, %{"error" => err}} -> {:error, err}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_logs(nil), do: ""

  defp fetch_logs(id) do
    escaped = String.replace(id, "\"", "\\\"")

    case send_to_daemon(~s({"cmd":"logs","args":{"id":"#{escaped}"}})) do
      {:ok, %{"ok" => logs}} -> logs
      _ -> ""
    end
  end

  defp send_to_daemon(json) do
    path = Path.expand("~/.overmind/overmind.sock")

    case :gen_tcp.connect({:local, String.to_charlist(path)}, 0, [
           :binary,
           {:packet, :line},
           {:active, false}
         ]) do
      {:ok, sock} ->
        :gen_tcp.send(sock, json <> "\n")

        result =
          case :gen_tcp.recv(sock, 0, 5000) do
            {:ok, line} -> {:ok, :json.decode(String.trim(line))}
            {:error, reason} -> {:error, reason}
          end

        :gen_tcp.close(sock)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private — rendering

  defp render(%{panel: :missions} = state) do
    clear()
    draw_header("Missions (#{length(state.missions)})", state)
    IO.write(Missions.render(state.missions, state.selected, state.width))
    draw_footer("j/k navigate  l/Enter logs  r refresh  ? help  q quit", state)
  end

  defp render(%{panel: :logs} = state) do
    clear()
    draw_header("Logs", state)
    IO.write(Logs.render(state.logs, state.selected_id, state.width, state.height))
    draw_footer("t missions  r refresh  q quit", state)
  end

  defp render(%{panel: :help} = state) do
    clear()
    draw_header("Help — Nexus", state)
    IO.write("  j / k    navigate missions\r\n")
    IO.write("  l        show logs for selected mission\r\n")
    IO.write("  Enter    show logs for selected mission\r\n")
    IO.write("  t        back to missions\r\n")
    IO.write("  r        refresh\r\n")
    IO.write("  ?        show this help\r\n")
    IO.write("  q        quit\r\n")
    draw_footer("press any key to continue", state)
  end

  defp clear, do: IO.write("\e[2J\e[H")

  defp draw_header(title, %{error: nil}) do
    IO.write("\e[7m Nexus | #{title} \e[0m\r\n\r\n")
  end

  defp draw_header(title, state) do
    IO.write("\e[7m Nexus | #{title} \e[0m  \e[31m#{state.error}\e[0m\r\n\r\n")
  end

  # Move cursor to bottom row for footer hints
  defp draw_footer(hints, state) do
    IO.write("\e[#{state.height - 1};0H\e[2m  #{hints}\e[0m")
  end

  defp terminal_size do
    rows = System.get_env("LINES", "24") |> String.to_integer()
    cols = System.get_env("COLUMNS", "80") |> String.to_integer()
    {rows, cols}
  end

  defp maybe_start_reader(_pid, _skip = true), do: :ok
  defp maybe_start_reader(pid, _skip = false), do: spawn(fn -> read_stdin(pid) end)

  defp read_stdin(app_pid) do
    case IO.read(:stdio, 1) do
      :eof ->
        send(app_pid, {:key, :eof})

      {:error, _} ->
        send(app_pid, {:key, :eof})

      char ->
        send(app_pid, {:key, char})
        read_stdin(app_pid)
    end
  end
end
