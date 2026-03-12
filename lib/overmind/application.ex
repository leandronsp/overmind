defmodule Overmind.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    :ets.new(:overmind_missions, [:set, :public, :named_table])
    :ets.new(:overmind_quests, [:set, :public, :named_table])
    :ets.new(:overmind_rituals, [:set, :public, :named_table])
    :ets.new(:port_registry, [:set, :public, :named_table])

    children =
      [
        {DynamicSupervisor, name: Overmind.MissionSupervisor, strategy: :one_for_one},
        Overmind.Ritual.Scheduler
      ] ++ optional_children()

    opts = [strategy: :one_for_one, name: Overmind.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # M5/M6 children that depend on NIFs or Phoenix — skip in escript mode.
  defp optional_children do
    children = []

    children =
      if Code.ensure_loaded?(Exqlite.Sqlite3NIF),
        do: children ++ [Overmind.Akasha.Store],
        else: children

    children =
      if Code.ensure_loaded?(Phoenix.PubSub),
        do: children ++ [{Phoenix.PubSub, name: Overmind.PubSub}],
        else: children

    if Code.ensure_loaded?(Phoenix.Endpoint),
      do: children ++ [OvermindWeb.Endpoint],
      else: children
  end
end
