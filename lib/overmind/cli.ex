defmodule Overmind.CLI do
  @moduledoc false

  @spec main([String.t()]) :: :ok
  def main(args) do
    case args do
      ["start"] -> Overmind.Daemon.start()
      ["shutdown"] -> Overmind.Daemon.shutdown()
      ["__daemon__"] -> Overmind.Daemon.run_daemon()
      ["claude", "run" | rest] -> cmd_claude_run(rest)
      ["run" | rest] -> cmd_run(rest)
      ["ps"] -> cmd_ps()
      ["logs", id] -> cmd_logs(id)
      ["stop", id] -> cmd_stop(id)
      ["kill", id] -> cmd_kill(id)
      [] -> print_usage()
      [cmd | _] -> unknown_command(cmd)
    end
  end

  defp cmd_run([]) do
    IO.puts("Missing command. Usage: overmind run <command>")
  end

  defp cmd_run(args) do
    command = Enum.join(args, " ")

    case execute(Overmind, :run, [command]) do
      {:ok, id} -> IO.puts("Started mission #{id}")
      {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
      :daemon_error -> :ok
    end
  end

  defp cmd_claude_run([]) do
    IO.puts("Missing prompt. Usage: overmind claude run <prompt>")
  end

  defp cmd_claude_run(args) do
    prompt = Enum.join(args, " ")

    case execute(Overmind, :run, [prompt, Overmind.Provider.Claude]) do
      {:ok, id} -> IO.puts("Started mission #{id}")
      {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
      :daemon_error -> :ok
    end
  end

  defp cmd_ps do
    case execute(Overmind, :ps, []) do
      :daemon_error ->
        :ok

      missions ->
        IO.puts(
          String.pad_trailing("ID", 12) <>
            String.pad_trailing("STATUS", 12) <>
            String.pad_trailing("UPTIME", 10) <>
            "COMMAND"
        )

        Enum.each(missions, fn m ->
          IO.puts(
            String.pad_trailing(m.id, 12) <>
              String.pad_trailing(Atom.to_string(m.status), 12) <>
              String.pad_trailing(format_uptime(m.uptime), 10) <>
              m.command
          )
        end)
    end
  end

  defp cmd_logs(id) do
    case execute(Overmind, :logs, [id]) do
      {:ok, logs} -> IO.write(logs)
      {:error, :not_found} -> IO.puts("Mission #{id} not found")
      :daemon_error -> :ok
    end
  end

  defp cmd_stop(id) do
    case execute(Overmind, :stop, [id]) do
      :ok -> IO.puts("Stopped mission #{id}")
      {:error, :not_found} -> IO.puts("Mission #{id} not found")
      {:error, :not_running} -> IO.puts("Mission #{id} is not running")
      :daemon_error -> :ok
    end
  end

  defp cmd_kill(id) do
    case execute(Overmind, :kill, [id]) do
      :ok -> IO.puts("Killed mission #{id}")
      {:error, :not_found} -> IO.puts("Mission #{id} not found")
      :daemon_error -> :ok
    end
  end

  defp execute(mod, fun, args) do
    dispatch_execute(direct_mode?(), mod, fun, args)
  end

  defp dispatch_execute(_direct = true, mod, fun, args) do
    apply(mod, fun, args)
  end

  defp dispatch_execute(_via_daemon = false, mod, fun, args) do
    with :ok <- Overmind.Daemon.connect() do
      case Overmind.Daemon.rpc(mod, fun, args) do
        {:error, {:rpc_failed, reason}} ->
          IO.puts("RPC error: #{inspect(reason)}")
          :daemon_error

        result ->
          result
      end
    else
      {:error, :not_running} ->
        IO.puts("Daemon not running. Start with: overmind start")
        :daemon_error
    end
  end

  defp direct_mode? do
    Application.get_env(:overmind, :direct_mode, false)
  end

  defp print_usage do
    IO.puts("""
    Overmind v0.1.0 — Kubernetes for AI Agents

    Usage: overmind <command> [options]

    Commands:
      start                    Start the daemon
      shutdown                 Stop the daemon
      run <command>            Spawn a raw command
      claude run <prompt>      Spawn a Claude agent
      ps                       List all missions
      logs <id>                Show mission logs
      stop <id>                Stop a mission (SIGTERM)
      kill <id>                Kill a mission (SIGKILL)\
    """)
  end

  defp unknown_command(cmd) do
    IO.puts("Unknown command: #{cmd}\n")
    print_usage()
  end

  defp format_uptime(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_uptime(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp format_uptime(seconds), do: "#{div(seconds, 3600)}h"
end
