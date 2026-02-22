# Roadmap

| Milestone | Name | Deliverable | Innovative? |
|---|---|---|---|
| M0 | Spawn & Observe | `overmind run`, `overmind ps`, `overmind logs`. Vanilla Elixir, no Phoenix, no worktree. Replaces tmux for a single agent. | No --- necessary foundation |
| M1 | Human-in-the-Loop | `overmind send`, `overmind attach`. PTY injection to talk to a running agent. | Partially --- AgentManager has similar |
| M2 | Self-Healing | Weaver loop. Restart policy (always/on-failure/never), exponential backoff, visible restart count. | No --- AgentManager has it |
| M3 | Declarative Config | Blueprint TOML. `overmind apply`, `overmind agents`. K8s-like semantics. | Partially --- others have config, not the k8s abstraction |
| M4 | Full Isolation | Mandatory worktree + dynamic port allocation + Docker for services. `.overmind.yml` as the environment contract. | **Yes** --- confirmed gap, no one has closed it |
| M5 | Shared Akasha | Optional remote Cortex. Team-accumulated codebase memory. Semantically queryable. | **Yes** --- core competitive differentiator |
| M6 | Web Dashboard | Phoenix + LiveView. Visual control tower. Sessions, logs, memory, worktrees in real time. | No --- Crystal and AgentManager have dashboards |
| M7 | Quest & Ritual | One-shot jobs and cron. `overmind quest run`, `overmind rituals`. | No --- standard in orchestrators |
| M8 | TUI (nexus) | `overmind tui`. k9s-like, vim navigation, panels for sessions/logs/memory. | Partially --- ccswarm has TUI, none have k9s-level DX |
