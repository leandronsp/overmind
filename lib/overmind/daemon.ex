defmodule Overmind.Daemon do
  @moduledoc false

  @node_name :overmind_daemon
  @cookie :overmind

  @spec start() :: :ok
  def start do
    start_daemon(alive?())
  end

  @spec run_daemon() :: no_return()
  def run_daemon do
    ensure_epmd()
    Node.start(@node_name, name_domain: :shortnames)
    Node.set_cookie(@cookie)
    Process.sleep(:infinity)
  end

  @spec connect() :: :ok | {:error, :not_running}
  def connect do
    ensure_distributed()

    case Node.connect(daemon_node()) do
      true -> :ok
      false -> {:error, :not_running}
      :ignored -> :ok
    end
  end

  @spec rpc(module(), atom(), [term()]) :: term()
  def rpc(module, function, args) do
    case :rpc.call(daemon_node(), module, function, args) do
      {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
      result -> result
    end
  end

  @spec shutdown() :: :ok
  def shutdown do
    case connect() do
      :ok ->
        :rpc.call(daemon_node(), :init, :stop, [])
        cleanup_pid_file()
        IO.puts("Daemon stopped")

      {:error, _} ->
        IO.puts("Daemon not running")
    end

    :ok
  end

  @spec alive?() :: boolean()
  def alive? do
    case File.read(pid_file()) do
      {:ok, pid_str} ->
        pid = String.trim(pid_str)
        {_, exit_code} = System.cmd("kill", ["-0", pid], stderr_to_stdout: true)
        exit_code == 0

      {:error, _} ->
        false
    end
  end

  defp start_daemon(_already_running = true) do
    IO.puts("Daemon is already running")
    :ok
  end

  defp start_daemon(_not_running = false) do
    File.mkdir_p!(pid_dir())
    ensure_epmd()

    escript = escript_path()

    {output, _} =
      System.cmd("sh", [
        "-c",
        "nohup #{escript} __daemon__ > #{log_file()} 2>&1 & echo $!"
      ])

    os_pid = String.trim(output)
    File.write!(pid_file(), os_pid)

    case wait_for_daemon(20) do
      :ok -> IO.puts("Daemon started (PID #{os_pid})")
      :timeout -> IO.puts("Daemon process started but not yet reachable")
    end

    :ok
  end

  defp ensure_epmd do
    System.cmd("epmd", ["-daemon"], stderr_to_stdout: true)
  end

  defp ensure_distributed do
    maybe_start_distribution(Node.alive?())
  end

  defp maybe_start_distribution(_already_distributed = true), do: :ok

  defp maybe_start_distribution(_needs_distribution = false) do
    name = :"overmind_cli_#{:rand.uniform(1_000_000)}"
    Node.start(name, name_domain: :shortnames)
    Node.set_cookie(@cookie)
  end

  defp daemon_node do
    {:ok, hostname} = :inet.gethostname()
    :"#{@node_name}@#{hostname}"
  end

  defp wait_for_daemon(0), do: :timeout

  defp wait_for_daemon(n) do
    Process.sleep(250)

    case connect() do
      :ok -> :ok
      {:error, _} -> wait_for_daemon(n - 1)
    end
  end

  defp escript_path do
    :escript.script_name() |> to_string()
  end

  defp pid_dir, do: Path.expand("~/.overmind")
  defp pid_file, do: Path.join(pid_dir(), "daemon.pid")
  defp log_file, do: Path.join(pid_dir(), "daemon.log")

  defp cleanup_pid_file do
    File.rm(pid_file())
  end
end
