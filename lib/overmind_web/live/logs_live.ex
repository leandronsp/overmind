defmodule OvermindWeb.LogsLive do
  @moduledoc false
  use Phoenix.LiveView, layout: {OvermindWeb.Layouts, :app}

  @refresh_ms 2_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)
    {:ok, assign(socket, id: id, name: resolve_name(id), logs: fetch_logs(id))}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, logs: fetch_logs(socket.assigns.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <a class="back" href="/">← All missions</a>
    <h1>Logs — {if @name, do: @name, else: @id}</h1>
    <pre>{@logs}</pre>
    """
  end

  defp fetch_logs(id) do
    case Overmind.logs(id) do
      {:ok, logs} -> logs
      {:error, _} -> "Mission not found or no logs yet."
    end
  end

  defp resolve_name(id) do
    case Overmind.Mission.Store.lookup_name(id) do
      nil -> nil
      name -> name
    end
  end
end
