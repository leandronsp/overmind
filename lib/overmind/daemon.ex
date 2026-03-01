defmodule Overmind.Daemon do
  @moduledoc false

  @spec run_daemon() :: no_return()
  def run_daemon do
    Overmind.APIServer.start_link()
    Process.sleep(:infinity)
  end
end
