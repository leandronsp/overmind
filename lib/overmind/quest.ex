defmodule Overmind.Quest do
  @moduledoc false

  @table :overmind_quests

  @type status :: :running | :completed | :failed

  @type t :: %{
    id: String.t(),
    name: String.t(),
    command: String.t(),
    status: status(),
    mission_id: String.t() | nil,
    created_at: integer()
  }

  # Quests run exactly once with no restart policy.
  @spec run(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def run(name, command) do
    quest_id = generate_id()
    created_at = System.system_time(:second)

    case Overmind.run(command, restart_policy: :never) do
      {:ok, mission_id} ->
        :ets.insert(@table, {quest_id, name, command, mission_id, created_at})
        {:ok, quest_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec list() :: [t()]
  def list do
    :ets.tab2list(@table)
    |> Enum.filter(&match?({_, _, _, _, _}, &1))
    |> Enum.map(&to_map/1)
    |> Enum.map(&hydrate_status/1)
  end

  @spec status(String.t()) :: {:ok, t()} | {:error, :not_found}
  def status(quest_id) do
    case :ets.lookup(@table, quest_id) do
      [entry] -> {:ok, entry |> to_map() |> hydrate_status()}
      [] -> {:error, :not_found}
    end
  end

  # Private

  defp generate_id do
    :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
  end

  defp to_map({id, name, command, mission_id, created_at}) do
    %{id: id, name: name, command: command, status: :running, mission_id: mission_id, created_at: created_at}
  end

  # Dynamically resolve quest status from the linked mission's current state.
  # Avoids a separate GenServer — status is derived on read.
  defp hydrate_status(%{mission_id: nil} = quest) do
    %{quest | status: :failed}
  end

  defp hydrate_status(%{mission_id: mission_id} = quest) do
    case Overmind.Mission.Store.lookup(mission_id) do
      {:running, _, _, _} -> %{quest | status: :running}
      {:restarting, _, _, _} -> %{quest | status: :running}
      {:exited, _, _, _} -> resolve_exit_status(quest, mission_id)
      :not_found -> %{quest | status: :failed}
    end
  end

  defp resolve_exit_status(quest, mission_id) do
    case Overmind.Mission.Store.lookup_exit_code(mission_id) do
      0 -> %{quest | status: :completed}
      _ -> %{quest | status: :failed}
    end
  end
end
