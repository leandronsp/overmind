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
│       ├── mission/
│       │   └── store.ex         # ETS operations for mission state
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
│   │   ├── mission/
│   │   │   └── store_test.exs
│   │   └── provider/
│   │       ├── raw_test.exs
│   │       └── claude_test.exs
│   └── support/                 # Test helpers (TestClaude provider, MissionHelper)
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

## Elixir Style

### Control Flow
- Prefer multi-clause functions with pattern matching over `if/else`, `unless`, `cond`
- Use `case` only when matching on an already-computed value (ETS result, GenServer reply)
- Use guard clauses (`when`) for type/range checks on function arguments
- Name multi-clause dispatch helpers descriptively, use underscored params for boolean semantics:
  `defp start_daemon(_already_running = true)`
- Extract repeated inline `if` into small helpers: `maybe_append/2`, `flush_line_buffer/2`

### Anti-patterns — DO NOT
- `if/else` for boolean dispatch — use multi-clause functions instead
- `unless` — use multi-clause with negated match or guard
- Deeply nested `case` inside `case` — extract inner match to a helper function
- `cond` when matching a single value — use `case` or function heads
- `do_something(true/false)` naming — use descriptive names
- Inline `if x, do: a, else: b` for nil checks — use `maybe_x(nil)` / `maybe_x(val)` pattern
- God modules (>200 lines) — extract submodules (e.g., Mission.Store)
- Duplicated code across files — extract to shared helper in `test/support/` or `lib/`

## TDD

- Write tests BEFORE or alongside implementation, never after
- Run `mix test` after every meaningful change, not just at the end
- Test public API only — do not test private functions directly
- One assertion focus per test (multiple asserts OK if testing one logical thing)
- Use `describe` blocks to group by function/feature
- Use `setup` for shared state, extract to `test/support/` if used across files
- Prefer `assert_receive` with monitors over `Process.sleep` for async assertions
- Run `mix dialyzer` before committing — typespecs are tests too
- E2E tests (`mix e2e`) validate the full daemon + CLI integration

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

