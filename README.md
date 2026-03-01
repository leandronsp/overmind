<p align="center">
  <img src="assets/cover.jpg" alt="Aerial view of tree branches spreading like a mycelium network" width="600" />
  <br />
  <sub>Photo by <a href="https://unsplash.com/@photoken123">Ian</a> on <a href="https://unsplash.com/photos/an-aerial-view-of-a-tree-in-a-forest-oiiTisRnAQk">Unsplash</a></sub>
</p>

# Overmind

Kubernetes for AI Agents.

A local-first runtime that treats AI agents as supervised processes with scheduling, observability, and self-healing. Think k9s for AI agent sessions.

### The Mycelium Network

Beneath every forest floor lies an invisible network — the mycelium. A single organism connecting thousands of trees, sharing resources, signaling threats, keeping the ecosystem alive. No central server. No single point of failure. Each node autonomous, yet part of something larger.

Overmind works the same way. Each AI agent is a supervised process — autonomous in execution, connected through a shared runtime. When one fails, the network heals itself. When one needs resources, the orchestrator provides. The intelligence isn't in any single agent. It's in the connections between them.

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
overmind ps --tree                                   # show parent-child hierarchy
overmind info <id>                                   # show mission info (os_pid, status)
overmind logs <id>                                   # show mission output
overmind stop <id>                                   # graceful stop (SIGTERM)
overmind kill <id>                                   # force kill (SIGKILL)
overmind kill --cascade <id>                         # kill with all children
overmind wait <id>                                   # block until mission exits
overmind shutdown                                    # stop the daemon
```

### Self-Healing

```bash
overmind run --restart on-failure --max-restarts 3 "flaky-script"
overmind run --restart always --backoff 2000 "long-running-worker"
overmind run --activity-timeout 60 "sleep 999"       # kill if no output for 60s
```

### Orchestration

```bash
overmind run --parent <id> "subtask"                 # spawn as child of parent
overmind wait <id>                                   # block until mission completes
overmind ps --tree                                   # visualize hierarchy
overmind kill --cascade <id>                         # depth-first kill tree
```

## Testing

```bash
mix test           # unit tests (auto-rebuilds escript)
mix dialyzer       # typespec checking
mix smoke          # quick smoke test (build, start, run, ps, shutdown)
mix e2e            # full E2E tests (daemon, raw commands, claude, sessions)
```

## Roadmap

| Milestone | Name | Status |
|-----------|------|--------|
| **M0** | Spawn & Observe | Done |
| **M0.5** | CWD + Names | Done |
| **M1** | Session Agents | Done |
| **M2** | Self-Healing | Done |
| **M2.5** | Orchestration Primitives | Done |
| M3 | Declarative Config | Next |
| M4 | Full Isolation | |
| M5 | Shared Akasha | |
| M6 | Web Dashboard | |
=======
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

[AGPL-3.0](LICENSE) — free to use, modify, and distribute. If you modify and offer as a network service, you must open your source code.

Copyright (c) 2026 Leandro Proenca.
