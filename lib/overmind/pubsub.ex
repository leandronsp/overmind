defmodule Overmind.PubSub do
  @moduledoc false

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(mission_id) do
    case Registry.register(Overmind.PubSub.Registry, mission_id, nil) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec broadcast(String.t(), term()) :: :ok
  def broadcast(mission_id, message) do
    Registry.dispatch(Overmind.PubSub.Registry, mission_id, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end
end
