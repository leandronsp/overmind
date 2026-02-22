defmodule Overmind.CLI do
  @moduledoc false

  @spec main([String.t()]) :: :ok
  def main(args) do
    case args do
      ["run" | rest] -> cmd_run(rest)
      ["ps"] -> cmd_ps()
      ["logs", id] -> cmd_logs(id)
      ["stop", id] -> cmd_stop(id)
      ["kill", id] -> cmd_kill(id)
      [] -> print_usage()
      [cmd | _] -> unknown_command(cmd)
    end
  end

  defp cmd_run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [agent: :string])

    case Keyword.get(opts, :agent) do
      nil ->
        IO.puts("Missing --agent option")

      command ->
        case Overmind.run(command) do
          {:ok, id} -> IO.puts("Started session #{id}")
          {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
        end
    end
  end

  defp cmd_ps do
    sessions = Overmind.ps()

    IO.puts(
      String.pad_trailing("ID", 12) <>
        String.pad_trailing("STATUS", 12) <>
        String.pad_trailing("UPTIME", 10) <>
        "COMMAND"
    )

    Enum.each(sessions, fn s ->
      IO.puts(
        String.pad_trailing(s.id, 12) <>
          String.pad_trailing(Atom.to_string(s.status), 12) <>
          String.pad_trailing(format_uptime(s.uptime), 10) <>
          s.command
      )
    end)
  end

  defp cmd_logs(id) do
    case Overmind.logs(id) do
      {:ok, logs} -> IO.write(logs)
      {:error, :not_found} -> IO.puts("Session #{id} not found")
    end
  end

  defp cmd_stop(id) do
    case Overmind.stop(id) do
      :ok -> IO.puts("Stopped session #{id}")
      {:error, :not_found} -> IO.puts("Session #{id} not found")
      {:error, :not_running} -> IO.puts("Session #{id} is not running")
    end
  end

  defp cmd_kill(id) do
    case Overmind.kill(id) do
      :ok -> IO.puts("Killed session #{id}")
      {:error, :not_found} -> IO.puts("Session #{id} not found")
      {:error, :not_running} -> IO.puts("Session #{id} is not running")
    end
  end

  defp print_usage do
    IO.puts("""
    Overmind v0.1.0 — Kubernetes for AI Agents

    Usage: overmind <command> [options]

    Commands:
      run --agent <cmd>   Spawn an agent process
      ps                  List all sessions
      logs <id>           Show session logs
      stop <id>           Stop a session (SIGTERM)
      kill <id>           Kill a session (SIGKILL)\
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
