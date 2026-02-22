defmodule Overmind.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    :ets.new(:overmind_missions, [:set, :public, :named_table])

    children = [
      {DynamicSupervisor, name: Overmind.MissionSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Overmind.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
