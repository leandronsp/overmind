# Overmind

Kubernetes for AI Agents.

A local-first runtime that treats AI agents as supervised processes with scheduling, observability, and shared memory. Think k9s for AI agent sessions.

## Install

Requires Erlang/OTP 28+ and Elixir 1.19.5+.

```bash
mix build          # compile escript binary
sudo ln -sf "$(pwd)/bin/overmind" /usr/local/bin/overmind
overmind start     # start the daemon
```

## Usage

```bash
overmind run "echo hello"                           # spawn a raw command
overmind run --name worker --cwd ~/project "make"   # named, with working directory
overmind claude run "explain OTP"                    # spawn a Claude agent
overmind run --type session --provider claude        # interactive Claude session
overmind send <id> "message"                         # send message to session
overmind attach <id>                                 # attach to session (TUI)
overmind ps                                          # list all missions
overmind info <id>                                   # show mission info (os_pid, status)
overmind logs <id>                                   # show mission output
overmind stop <id>                                   # graceful stop (SIGTERM)
overmind kill <id>                                   # force kill (SIGKILL)
overmind shutdown                                    # stop the daemon
```

### Self-Healing

```bash
overmind run --restart on-failure --max-restarts 3 "flaky-script"
overmind run --restart always --backoff 2000 "long-running-worker"
overmind run --activity-timeout 60 "sleep 999"       # kill if no output for 60s
```

## Testing

```bash
mix test           # unit tests (auto-rebuilds escript)
mix e2e            # full E2E tests (daemon, raw commands, claude)
```

## Roadmap

| Milestone | Name | Description |
|-----------|------|-------------|
| **M0** | **Spawn & Observe** | **`run`, `ps`, `logs`, `stop`, `kill`, daemon, providers** |
| **M0.5** | **CWD + Names** | **`--cwd`, `--name`, auto-generated names, name resolution** |
| **M1** | **Session Agents** | **`--type session`, multi-turn agents, `send`, `attach`** |
| **M2** | **Self-Healing** | **Restart policies, exponential backoff, stall detection** |
| M2.5 | Agent Orchestration | Orchestrator pattern, optional hierarchy (`--parent`), `kill --cascade` |
| M3 | Declarative Config | Blueprint TOML, `overmind apply` |
| M4 | Full Isolation | Worktree + port allocation + Docker services |
| M5 | Shared Akasha | Distributed codebase memory |
| M6 | Web Dashboard | Phoenix LiveView |

## License

MIT
