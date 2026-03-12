defmodule Overmind.Isolation.PortRegistry do
  @moduledoc false

  @table :port_registry
  @port_min 3100
  @port_max 3999

  @spec allocate(String.t(), String.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :exhausted}
  def allocate(mission_id, service_name, _base_port) do
    used = used_ports()
    find_free_port(mission_id, service_name, @port_min, used)
  end

  @spec release(String.t()) :: :ok
  def release(mission_id) do
    :ets.match_delete(@table, {:_, mission_id, :_, :_})
    :ok
  end

  @spec list() :: [{non_neg_integer(), String.t(), String.t(), integer()}]
  def list do
    :ets.tab2list(@table)
  end

  # Private

  defp used_ports do
    :ets.tab2list(@table)
    |> Enum.map(fn {port, _, _, _} -> port end)
    |> MapSet.new()
  end

  defp find_free_port(_, _, port, _) when port > @port_max, do: {:error, :exhausted}

  defp find_free_port(mission_id, service_name, port, used) do
    case MapSet.member?(used, port) do
      true ->
        find_free_port(mission_id, service_name, port + 1, used)

      false ->
        :ets.insert(@table, {port, mission_id, service_name, System.system_time(:second)})
        {:ok, port}
    end
  end
end
