defmodule OvermindWeb.MissionLive do
  @moduledoc false
  use Phoenix.LiveView, layout: {OvermindWeb.Layouts, :app}

  @refresh_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)
    {:ok, assign(socket, missions: Overmind.ps())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, missions: Overmind.ps())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Overmind Dashboard</h1>
    <%= if @missions == [] do %>
      <p class="empty">No missions running.</p>
    <% else %>
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Name</th>
            <th>Status</th>
            <th>Type</th>
            <th>Uptime</th>
            <th>Command</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={m <- @missions}>
            <td><a href={"/missions/#{m.id}/logs"}>{String.slice(m.id, 0, 8)}</a></td>
            <td>{m.name}</td>
            <td class={"status-#{m.status}"}>{m.status}</td>
            <td>{m.type}</td>
            <td>{m.uptime}s</td>
            <td>{m.command}</td>
          </tr>
        </tbody>
      </table>
    <% end %>
    """
  end
end
