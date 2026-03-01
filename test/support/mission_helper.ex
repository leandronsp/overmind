defmodule Overmind.Test.MissionHelper do
  @moduledoc false

  def cleanup_missions do
    for status <- [:running, :restarting] do
      :ets.match(:overmind_missions, {:"$1", :_, :_, status, :_})
      |> List.flatten()
      |> Enum.each(fn id ->
        case :ets.lookup(:overmind_missions, id) do
          [{_, pid, _, _, _}] when is_pid(pid) ->
            if Process.alive?(pid) do
              try do
                GenServer.stop(pid, :normal, 100)
              catch
                :exit, _ -> :ok
              end
            end

          _ ->
            :ok
        end
      end)
    end

    :ets.delete_all_objects(:overmind_missions)
    Process.sleep(10)
  end
end
