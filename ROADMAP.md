# Roadmap

| Milestone | Name | Deliverable | Innovative? |
|---|---|---|---|
| M0 | Spawn & Observe | `overmind run`, `overmind ps`, `overmind logs`, `overmind stop`, `overmind kill`. Daemon mode, providers (raw + claude). | No --- necessary foundation |
| M1 | Session Agents | `--type session`, long-running multi-turn agents via bidirectional stream-json. `overmind send`, `overmind attach` (hybrid PTY — full Claude TUI via `--resume`). | Partially --- AgentManager has similar |
| M2 | Self-Healing | Restart policy (always/on-failure/never), exponential backoff, visible restart count, stall detection via activity timeout, session recovery via `--session-id`. | No --- AgentManager has it |
| M2.5 | Orchestration Loop | Supervised Ralph Loop — session agent as orchestrator running decompose → spawn → wait → validate → record → next. `overmind wait`, `--parent`, `ps --tree`, `kill --cascade`. Parallel and sequential strategies, emergent via skill. | **Yes** --- no tool has a supervised, parallel orchestration loop with OTP semantics |
| M3 | Declarative Config | Blueprint TOML. `overmind apply`, `overmind agents`. K8s-like semantics. Deterministic orchestration mode via `depends_on` DAG — alternative to LLM-driven loop (M2.5). Both modes use the same primitives (wait, --parent, --cascade). | Partially --- others have config, not the k8s abstraction + deterministic orchestration |
| M4 | Full Isolation | Mandatory worktree + dynamic port allocation + Docker for services. `.overmind.yml` as the environment contract. | **Yes** --- confirmed gap, no one has closed it |
| M5 | Shared Akasha | Optional remote Cortex. Team-accumulated codebase memory. Semantically queryable. | **Yes** --- core competitive differentiator |
| M6 | Web Dashboard | Phoenix + LiveView. Visual control tower. Sessions, logs, memory, worktrees in real time. | No --- Crystal and AgentManager have dashboards |
| M7 | Quest & Ritual | One-shot jobs and cron. `overmind quest run`, `overmind rituals`. | No --- standard in orchestrators |
| M8 | TUI (nexus) | `overmind tui`. k9s-like, vim navigation, panels for sessions/logs/memory. | Partially --- ccswarm has TUI, none have k9s-level DX |
