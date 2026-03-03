defmodule Overmind.Daemon do
  @moduledoc false

  @spec run_daemon() :: no_return()
  def run_daemon do
    Application.put_env(:overmind, :started_at, System.system_time(:second))
    Overmind.APIServer.start_link()
    Process.sleep(:infinity)
  end
end
