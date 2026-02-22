# OVERMIND

*Kubernetes for AI Agents*

Product Requirements Document - v0.1 - February 2026

## 1. Vision

The GUI with windows and mouse has served us well. But as AI agents become capable of doing everything a human can on a computer, the operating system needs to evolve with them.

Overmind is a bi-modal runtime for AI agents: it helps agents work faster and more efficiently, and helps humans visualize and understand what is happening inside the machine. Think of it as Kubernetes for AI agents --- a standalone infrastructure layer that treats agents as first-class processes with scheduling, supervision, observability, and shared memory.

The closest analogy in the developer world: k9s gives you a tower-of-control over Kubernetes pods. Overmind gives you the same over AI agent sessions --- with restart policies, log streaming, worktree isolation, database isolation, and a shared memory layer that makes the entire team smarter over time.

## 2. Problem Statement

Developers running multiple AI agents today manage them with tmux, bash scripts, and manual babysitting. The pain points are concrete:

- An agent crashes --- you have to find the right tmux window, kill it manually, restart it. No automatic recovery.
- Logs are scattered across terminal windows with no centralized view or filtering.
- Multiple agents on the same repo conflict --- same ports, same database, same working directory.
- No way to send a message to a running agent without interrupting it.
- No memory sharing between agents or between dev sessions --- the team's accumulated knowledge lives only in CLAUDE.md files that are static and version-controlled, not dynamic.
- No primitives for recurring tasks (cron), one-shot jobs, or fleet management.

The gap the market has confirmed but not closed: no tool connects worktree code isolation with full environment isolation (database, ports, services). DevTree attempted it and failed. The Upsun developer blog explicitly listed this as the unsolved problem as of February 2026.

## 3. Solution Overview

Overmind is a local-first runtime (with optional distributed Cortex) that:

- Treats every AI agent as a supervised process with lifecycle management
- Provides worktree isolation as a mandatory design decision, not an option
- Automatically isolates databases and services per session via Docker and dynamic port allocation
- Streams logs centrally with session tagging and human-injected message markers
- Maintains a shared Akasha (knowledge store) that accumulates codebase understanding across sessions and team members
- Exposes a k9s-inspired TUI and a LiveView web dashboard for human observation and intervention

## 4. Core Primitives (k8s Mapping)

| Kubernetes | Overmind | Description |
|---|---|---|
| Cluster | Swarm | The full set of resources available to run agents |
| Node | Hive | A machine where agents execute. Runs the Hive Agent process. |
| Namespace | Colony | Logical grouping --- e.g. 'work', 'personal', 'research' |
| Pod | Session | One agent instantiated running one task. Ephemeral. |
| Container | Agent | Definition of what runs: command, system prompt, tools |
| Deployment | Fleet | Desired state: keep N Sessions of this Agent alive |
| ReplicaSet | Pack | Observed state: the actual running Sessions of a Fleet |
| StatefulSet | Lineage | Agent with persistent identity and memory between Sessions |
| Job | Quest | One-shot task: run, complete, done |
| CronJob | Ritual | Recurring Quest with cron schedule |
| DaemonSet | Sentinel | Agent that runs on every Hive (monitoring, health checks) |
| Service | Channel | How other agents or humans communicate with a Session |
| Ingress | Gateway | External entry point to the Swarm |
| ConfigMap | Context | Non-secret config injected into an Agent at runtime |
| Secret | Vault | API keys, tokens, credentials |
| Volume | Memory | Persistent storage mounted into a Session |
| PVC | MemoryClaim | Agent's declaration of persistent memory needs |
| Scheduler | Oracle | Decides where and when Sessions run |
| Controller Manager | Weaver | Reconciliation loop: desired state vs actual state |
| etcd | Akasha | Authoritative state store. ETS (hot) + SQLite (durable) |
| API Server | Cortex | Central API all components use to read/write Akasha |
| kubectl | overmind CLI | The command-line interface. `overmind ps`, `overmind logs` |
| k9s | overmind tui | Terminal UI. Vim-like navigation. Live panels. |
| Helm | Genome | Package manager for Blueprints |

## 5. Architecture

### 5.1 Local Mode (MVP)

All components run in a single Elixir Mix application. Cortex and Hive are logically separated GenServers but physically co-located. No Phoenix required until the web dashboard milestone.

Mix App -> Cortex (GenServer) -> Hive (GenServer) -> Session (GenServer) -> Port (OS process)

### 5.2 Distributed Mode (M5+)

Cortex moves to a remote server (or stays local). Hive Agents run on each developer's machine. The CLI and TUI always talk to the Cortex --- they never need to know where the Hive is. The Cortex<->Hive protocol is defined from day one so extraction is surgical, not a rewrite.

### 5.3 Akasha

Two-tier persistence: ETS for hot state (zero-latency reads for LiveView and TUI), SQLite for durability (event log, memory, session history). In distributed mode, SQLite is replaced by Postgres. Akasha is the source of truth the Weaver reconciliation loop reads from.

### 5.4 Worktree + Environment Isolation

Every Session is born in a git worktree. This is not optional --- it is the design. The `.overmind.yml` file at the project root declares services:

```yaml
services:
  web:
    command: bundle exec rails s -p $PORT
    port: 3000
  db:
    docker: postgres:16
    port: 5432
  cache:
    docker: redis:7
    port: 6379
isolation:
  strategy: ports
  port_range: 3100-3999
```

The `.overmind.yml` declares intent, not fixed values. Overmind's port registry allocates unique ports per Session and injects them as environment variables. The app never sees the values from the YAML --- it only sees the injected vars. Two Sessions of the same repo never conflict.

## 6. Roadmap

See [ROADMAP.md](../ROADMAP.md) for the full roadmap.

## 7. M0 --- Detailed Specification

M0 is the absolute minimum: spawn an agent and observe it. No worktree, no isolation, no Phoenix. Pure vanilla Elixir.

### 7.1 Commands

- `overmind run --agent <cmd> --project <path>` --- spawns process, captures stdout/stderr
- `overmind ps` --- lists active sessions with status (running/crashed/idle) and uptime
- `overmind logs <session-id>` --- real-time stream
- `overmind stop <session-id>` --- graceful stop
- `overmind kill <session-id>` --- force kill

### 7.2 Stack

- Elixir + Mix (no Phoenix)
- GenServer per Session --- wraps the Port (OS process)
- ETS for hot state (active sessions, status, metadata)
- Burrito for standalone binary compilation
- Owl or OptionParser for CLI

### 7.3 Session Lifecycle

- STARTING -> spawns Port with correct cwd
- RUNNING -> captures stdout/stderr, indexes in ETS
- CRASHED -> detects Port exit, updates status
- STOPPED -> explicit kill by user

## 8. M4 --- Isolation Specification

M4 is the differentiating milestone. It solves the gap no existing project has closed.

### 8.1 Session Lifecycle with Isolation

1. Read `.overmind.yml` from the project
2. Allocate unique ports in the Port Registry (ETS) for each declared service
3. Start Docker containers for dependent services with names derived from the session-id
4. Create git worktree: `git worktree add .overmind/worktrees/<branch> -b <branch>`
5. Spawn main process with all env vars injected
6. Teardown: stop containers -> release ports -> prompt about worktree (keep/remove)

### 8.2 Port Registry

ETS table `:port_registry` with schema `{port, session_id, service_name, allocated_at}`. Before each Session, scans the range declared in `.overmind.yml` and allocates free ports. Releases on teardown.

### 8.3 Apps without .overmind.yml

Fallback: injects only PORT as an environment variable with a unique allocated value. Works for Rails/Node/Python apps that honor PORT natively.

## 9. M5 --- Shared Akasha

The long-term competitive differentiator. Codebase memory that grows with team usage.

### 9.1 What Akasha Stores

- Session event log: which files were touched, which commands executed, which errors encountered
- Explicit memory: the agent writes decisions, identified patterns, codebase gotchas
- Feature context: history of previous implementations of similar features
- Semantic index: embeddings for search by meaning, not just keyword

### 9.2 Distribution Model

The runtime (Hive, Sessions, worktrees) is always local. Akasha can be local (SQLite) or remote (Postgres + Cortex server). In remote mode, all team devs point to the same Cortex --- memories are shared, but code stays on each machine.

### 9.3 Difference from CLAUDE.md

CLAUDE.md is static, version-controlled in git, manually edited. Akasha is dynamic --- it grows during Sessions, is automatically consulted before each new Session, and is shared without friction. CLAUDE.md continues to exist for the dev's declarative intentions. Akasha captures the emergent knowledge from usage.

## 10. Competitive Analysis

| Project | Stack | Worktree | DB Isolation | Shared Memory | Auto Restart | TUI | OSS |
|---|---|---|---|---|---|---|---|
| Claude Squad | Go | Yes | No | No | No | Yes (tmux) | MIT |
| CCManager | Go | Yes | No | Partial | No | Yes | MIT |
| Crystal | Electron | Yes | No | No | No | No (desktop) | MIT |
| ccswarm | Rust | Yes | No | No | Partial | Yes | MIT |
| AgentManager | Node/TS | GC only | No | Markdown/GCS | Yes | No | MIT |
| Composio AO | Node/TS | Yes | No | No | No | No | Apache 2.0 |
| Overmind | Elixir | Yes (M4) | Yes (M4) | Yes (M5) | Yes (M2) | Yes (M8) | MIT (proposed) |

Gap publicly confirmed by the Upsun Developer Center article (February 2026): "The gap no one has closed: no tool connects worktree code isolation with full environment isolation."

## 11. Monetization

Philosophy: OSS forever for the runtime. Revenue comes from the collaboration and operations layers that teams don't want to self-host.

### 11.1 Open Core

Core runtime (M0-M4) remains MIT forever. Enterprise features are paid:

- SSO and RBAC for teams (who can see which Colony, who can kill Sessions)
- Complete and immutable Akasha audit log (compliance)
- Policy engine: rules for what agents can and cannot do
- Dedicated support SLA

### 11.2 Akasha Cloud

The Tailscale model: OSS client, paid coordination server. The remote Cortex (shared Akasha) is an operated service. Teams pay for:

- Number of active projects in Akasha
- Number of devs connected to the same Cortex
- Memory volume and historical retention

This is the most natural and defensible model. Anthropic can't replace you here --- they have no incentive to operate a codebase memory server for teams.

### 11.3 Hosted Hive

For teams that want agents running on a shared server without managing infrastructure. Managed Hives in the cloud. Pay-per-session or monthly subscription. Use cases: agents running 24/7, CI/CD agents, monitoring agents.

### 11.4 Genome Marketplace

Community-curated packaged Blueprints. Basic Genomes are free. 'Verified' or specialized Genomes (e.g. 'Rails 8 full stack team') are paid or freemium.

## 12. Risk Analysis --- Anthropic / OpenAI

### 12.1 What Anthropic Has Already Absorbed

Worktrees in Claude Code, Agent Teams, Swarm Mode --- all were community patterns that Anthropic incorporated natively. This is the historical pattern.

### 12.2 What They Won't Build

Complete operational infrastructure primitives. Anthropic has no incentive to build Kubernetes. They provide the engine (Claude), not the orchestration. It's the same reason AWS didn't build Kubernetes --- they provided the building blocks, the community built the orchestration layer.

### 12.3 The Real Risk

It's not copying --- it's timing. The risk is not building M4 publicly fast enough to be the first to have environment isolation working and documented. Once you are the public reference, being absorbed by Anthropic is a positive outcome, not a negative one.

### 12.4 The Steinberger Model

Peter Steinberger built OpenClaw in public, went viral, and was hired by OpenAI to lead personal agent development. The code was open sourced to an independent foundation. He didn't sell the project --- he sold the proof that he understood the problem before everyone else. Building Overmind in public, with livestreams documenting the architectural decisions, is the same playbook.

## 13. Go-to-Market

### 13.1 Primary Channel

Live coding on Twitch/YouTube documenting each milestone. Each architectural decision becomes a post on leandronsp.com. The project is built in public from the first commit.

### 13.2 Livestream Strategy

- Live 1: present the problem, the full roadmap, justify the decisions (show everything --- plant the flag with a date)
- Lives 2-3: implement M0 live --- spawn, logs, ps
- Lives 4-5: M1 and M2 --- send message, automatic restart
- Lives 6+: M4 --- the differentiating milestone. Full isolation. This is the viral moment.

### 13.3 Positioning

"Kubernetes for AI agents. Open source. Terminal-first. For devs who already understand k8s and want the same DX for their agents."

## 14. Design Decision Q&A

**Why Elixir/Phoenix and not Rust or Go?**

The BEAM is natively a runtime of supervised concurrent processes that communicate by messages --- which is exactly the model of an agent scheduler. GenServer, OTP supervision, ETS, and Phoenix PubSub solve the core problems without inventing anything. Rust would be more performant but more verbose for this problem. Go would be reasonable but lacks native supervision.

**Why not use k8s directly?**

K8s was designed for stateless HTTP services that scale horizontally. LLM agents are long-running stateful conversational processes with human-in-the-loop. The mismatch is real: containerizing each agent, managing interactive stdin/stdout in Pods, instrumenting LLM observability --- all friction with no gain. Overmind uses the concepts of k8s, not the implementation.

**Why not ZeroMQ for Cortex<->Hive communication?**

The BEAM already has native distribution. Two Elixir nodes communicate via Node.connect with semantics identical to local GenServer. For Hive on a non-Elixir machine, Phoenix Channels via WebSocket is simpler than ZeroMQ and comes with automatic reconnection, presence, and a pre-defined protocol.

**Worktree as mandatory design, not an option --- why?**

Every Session without a worktree is an agent that can conflict with another. If it's an option, it will be disabled. If it's a design decision, it eliminates an entire class of bugs and conflicts from the start. The cost (git worktree add is a fast operation) is insignificant compared to the benefit.

**/etc/hosts for domain isolation --- good practice?**

Not for routine use. Requires sudo, is global (risk of leak between Sessions), and has race conditions if multiple processes write simultaneously. The correct alternative is dynamic port allocation with injected env vars. Local DNS via dnsmasq/resolver could be a future opt-in feature, but it's not the default.

**Does the port registry resolve conflicts between two agents on the same repo?**

Yes. The `.overmind.yml` declares intent (port 3000), not a fixed value. The port registry allocates dynamically before each Session and injects the vars. The app never sees the YAML value --- it only sees $PORT with a unique, free value. Two agents on the same repo never conflict because the registry guarantees uniqueness.

## 15. Next Steps

- Create public GitHub repository with README explaining the vision
- Implement M0: Session GenServer + Port + ETS + basic CLI
- Record Live 1: present the problem, the roadmap, the decisions --- plant the flag
- Iterate M1 and M2 in the next livestreams
- Write technical post about the decision to use BEAM for agent scheduling
- Define Cortex<->Hive protocol before M4 to ensure distributed extraction is surgical

*Overmind - PRD v0.1 - Leandro - February 2026 - OSS (MIT proposed)*
