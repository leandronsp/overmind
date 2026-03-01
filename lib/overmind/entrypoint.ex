defmodule Overmind.Entrypoint do
  @moduledoc false

  @spec main([String.t()]) :: :ok
  def main(["__daemon__"]), do: Overmind.Daemon.run_daemon()
  def main(_), do: IO.puts("Internal daemon entry point. Use bin/overmind instead.")
end
