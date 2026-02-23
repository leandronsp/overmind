defmodule Overmind.Test.MissionHelper do
  @moduledoc false

  def cleanup_missions do
    :ets.match(:overmind_missions, {:"$1", :_, :_, :running, :_})
    |> List.flatten()
    |> Enum.each(fn id ->
      case :ets.lookup(:overmind_missions, id) do
        [{_, pid, _, :running, _}] ->
          try do
            GenServer.stop(pid, :normal, 100)
          catch
            :exit, _ -> :ok
          end

        _ ->
          :ok
      end
    end)

    :ets.delete_all_objects(:overmind_missions)
    Process.sleep(10)
  end
end
