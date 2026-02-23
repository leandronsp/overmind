# Overmind

Kubernetes for AI Agents. Local-first runtime that treats AI agents as supervised processes.

## Stack

- **Elixir** — OTP supervision, GenServer, ETS
- **Mix** — build tool, escript for CLI binary
- **No Phoenix** until M6 (web dashboard)

## Project Structure

```
├── lib/
│   ├── overmind.ex              # Public API (run, ps, logs, stop, kill)
│   └── overmind/
│       ├── application.ex       # OTP Application (ETS + DynamicSupervisor)
│       ├── cli.ex               # Escript entry point, RPC to daemon
│       ├── daemon.ex            # Daemon lifecycle (start/shutdown/rpc)
│       ├── mission.ex           # GenServer per spawned process (Port)
│       ├── provider.ex          # Provider behaviour (build_command, parse_line, format_for_logs)
│       └── provider/
│           ├── raw.ex           # Raw shell commands (wraps with sh -c)
│           └── claude.ex        # Claude CLI (stream-json parsing)
├── test/
│   ├── test_helper.exs
│   ├── overmind_test.exs
│   ├── overmind/
│   │   ├── cli_test.exs
│   │   ├── mission_test.exs
│   │   └── provider/
│   │       ├── raw_test.exs
│   │       └── claude_test.exs
│   └── support/                 # Test helpers (TestClaude provider)
├── test_e2e.sh                  # E2E test script (daemon + raw + claude)
├── mix.exs
└── CLAUDE.md
```

## Architecture

- **Daemon mode**: CLI sends commands via Erlang distributed RPC to a long-running daemon process
- **Missions**: Each spawned command is a GenServer under DynamicSupervisor, managing a Port
- **Providers**: Pluggable command builders/parsers — Raw wraps with `sh -c`, Claude parses stream-json
- **ETS**: Mission state (status, logs, raw_events) persists after GenServer exits

## Build & Run

```bash
mix build            # compile escript binary (alias for mix escript.build)
./overmind start     # start the daemon
./overmind shutdown  # stop the daemon
mix test             # run unit tests (auto-rebuilds escript first)
mix e2e              # run E2E tests (builds, starts daemon, tests all commands)
```

`mix test` always rebuilds the escript before running tests — no stale binary risk.

## Code Standards

- Self-documenting function names, minimal comments
- `mix test` must pass before committing
- `mix dialyzer` must pass before committing
- No external deps unless strictly necessary

## Typespecs

Typespecs serve as deterministic constraints on LLM-generated code — the type checker rejects invalid output the same way a compiler rejects syntax errors.

### Rules

- `@type t :: %__MODULE__{}` on every struct
- `@spec` on all public client API functions (skip private helpers)
- Do NOT spec GenServer callbacks (`handle_call`, `handle_cast`, `handle_info`, `init`) — the behaviour's `@callback` specs handle this via `@impl true`
- Skip specs on CLI glue code and test helpers

### Type reference

| Use this | Not this | For |
|---|---|---|
| `String.t()` | `string()`, `binary()` | UTF-8 strings |
| `binary()` | | Raw bytes, Port output |
| `pid()` | `PID` | Process identifiers |
| `atom()` | | Atoms like `:running`, `:crashed` |
| `integer()` | `int()` | Integers |
| `non_neg_integer()` | | Counts, sizes, exit codes |
| `boolean()` | | true/false |
| `port()` | | Elixir Port references |
| `GenServer.on_start()` | | Return of `start_link` |
| `DynamicSupervisor.on_start_child()` | | Return of `start_child` |
| `term()` | `any()` | Unknown/generic values |
| `keyword()` | | Keyword lists `[key: val]` |
| `[type()]` | `list(type())` | Lists |
| `{:ok, t()} \| {:error, term()}` | | Tagged tuples (ok/error) |
| `MyModule.t()` | | Custom struct types |

## Git

- Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `chore:`
- Never mention AI/Claude in commits, no Co-Authored-By
- Stage specific files, never `git add .`

## Roadmap

- **M0** — Spawn & Observe (done): `run`, `ps`, `logs`, `stop`, `kill`, daemon mode, providers (raw + claude)
- **M1** — Human-in-the-Loop: `send`, `attach`
- **M2** — Self-Healing: restart policies, backoff
- **M3** — Declarative Config: Blueprint TOML
- **M4** — Full Isolation: worktree + port allocation + Docker
- **M5** — Shared Akasha: distributed memory
- **M6** — Web Dashboard: Phoenix LiveView

For detailed roadmap see `ROADMAP.md`. Full PRD at `docs/overmind_prd.md`.

