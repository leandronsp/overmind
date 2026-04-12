# Overmind

Kubernetes for AI Agents.

A local-first runtime that treats AI agents as supervised processes with scheduling, observability, and self-healing. Think k9s for AI agent sessions.

<p align="center">
  <img src="assets/cover.jpg" alt="Aerial view of tree branches spreading like a mycelium network" width="400" />
  <br />
  <sub>Photo by <a href="https://unsplash.com/@photoken123">Ian</a> on <a href="https://unsplash.com/photos/an-aerial-view-of-a-tree-in-a-forest-oiiTisRnAQk">Unsplash</a></sub>
</p>

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
overmind send <id> "msg" --wait                      # send and wait for response
overmind send <id> "msg" --wait --json               # return full result as JSON
overmind send <id> "msg" --wait --timeout 120000     # custom timeout (ms)
overmind subscribe <id>                              # stream events as NDJSON
overmind attach <id>                                 # attach to session (TUI)
overmind ps                                          # list all missions
overmind ps --tree                                   # show parent-child hierarchy
overmind info <id>                                   # show mission info (os_pid, status)
overmind logs                                        # show all mission logs
overmind logs <id>                                   # show mission logs
overmind stop <id>                                   # graceful stop (SIGTERM)
overmind kill <id>                                   # force kill (SIGKILL)
overmind kill --cascade <id>                         # kill with all children
overmind kill --all                                  # kill all missions
overmind wait <id>                                   # block until mission exits
overmind shutdown                                    # stop the daemon
```

### Self-Healing

```bash
overmind run --restart on-failure --max-restarts 3 "flaky-script"
overmind run --restart always --backoff 2000 "long-running-worker"
overmind run --activity-timeout 60 "sleep 999"       # kill if no output for 60s
```

### Declarative Config (Blueprint)

```bash
overmind agents pipeline.toml                        # list agents in blueprint
overmind apply pipeline.toml                         # run blueprint (async)
overmind wait <id>                                   # wait for pipeline to finish
overmind logs <id>                                   # pipeline execution logs
```

```toml
# pipeline.toml
[agents.researcher]
command = "list 3 facts about Elixir"
provider = "claude"

[agents.writer]
command = "write a summary"
provider = "claude"
depends_on = ["researcher"]
```

### Orchestration

```bash
overmind run --parent <id> "subtask"                 # spawn as child of parent
overmind wait <id>                                   # block until mission completes
overmind ps --tree                                   # visualize hierarchy
overmind kill --cascade <id>                         # depth-first kill tree
```

### Event Streaming

```bash
# Blocking send: wait for the agent to respond
overmind send <id> "fix the typos" --wait
# => "Fixed 3 typos in README.md"

# Full result as JSON (includes cost, duration)
overmind send <id> "fix the typos" --wait --json
# => {"text":"Fixed 3 typos","duration_ms":4200,"cost_usd":0.03}

# Subscribe to all events from a mission (NDJSON, one JSON object per line)
overmind subscribe <id>
# => {"type":"assistant","message":{"content":[{"type":"text","text":"Working on it..."}]}}
# => {"type":"result","result":"Done","duration_ms":100,"cost_usd":0.01}
# => {"type":"exit","status":"stopped","exit_code":0}
```

Programmatic PubSub from Elixir:

```elixir
Overmind.PubSub.subscribe(mission_id)

receive do
  {:mission_event, ^mission_id, {:text, text}, _raw} -> IO.puts(text)
  {:mission_exit, ^mission_id, status, code} -> IO.puts("Exited: #{status}")
end
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
| **M3** | Declarative Config | Done |
| **M3.5** | Event Streaming | Done |
| M4 | Full Isolation | |
| M5 | Shared Akasha | |
| M6 | Web Dashboard | |

## License

[AGPL-3.0](LICENSE) — free to use, modify, and distribute. If you modify and offer as a network service, you must open your source code.

Copyright (c) 2026 Leandro Proenca.
