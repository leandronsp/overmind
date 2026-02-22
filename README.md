# Overmind

Kubernetes for AI Agents.

A local-first runtime that treats AI agents as supervised processes with scheduling, observability, and shared memory. Think k9s for AI agent sessions.

## Install

Requires Erlang/OTP 28+ and Elixir 1.19.5+.

```bash
mix build      # compile escript binary
./overmind     # run CLI
```

`mix test` automatically rebuilds the escript before running, so the binary is never stale.

## Roadmap

| Milestone | Name | Description |
|-----------|------|-------------|
| M0 | Spawn & Observe | `run`, `ps`, `logs`, `stop`, `kill` |
| M1 | Human-in-the-Loop | `send`, `attach` |
| M2 | Self-Healing | Restart policies, exponential backoff |
| M3 | Declarative Config | Blueprint TOML, `overmind apply` |
| M4 | Full Isolation | Worktree + port allocation + Docker services |
| M5 | Shared Akasha | Distributed codebase memory |
| M6 | Web Dashboard | Phoenix LiveView |

## License

MIT
