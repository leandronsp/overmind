# Overmind

Kubernetes for AI Agents. Local-first runtime that treats AI agents as supervised processes.

## Stack

- **Elixir** — OTP supervision, GenServer, ETS
- **Mix** — build tool, escript for CLI binary
- **No Phoenix** until M6 (web dashboard)

## Project Structure

```
├── bin/
│   ├── overmind               # Shell script CLI (dispatch + source)
│   └── cli/
│       ├── helpers.sh         # JSON helpers (escape, send_cmd, extract_ok, maybe_json_*)
│       ├── commands.sh        # All cmd_* functions (run, ps, logs, attach, etc.)
│       └── orchestration.sh  # Orchestration commands (wait)
├── lib/
│   ├── overmind.ex              # Public API (run, ps, logs, stop, kill, wait, children)
│   └── overmind/
│       ├── application.ex       # OTP Application (ETS + DynamicSupervisor)
│       ├── entrypoint.ex        # Escript entry point (daemon bootstrap only)
│       ├── daemon.ex            # Daemon runner (starts APIServer, sleeps forever)
│       ├── formatter.ex         # PS table and tree rendering (format_ps, format_ps_tree)
│       ├── mission.ex           # GenServer per spawned process (Port)
│       ├── mission/
│       │   ├── client.ex        # Client API (get_logs, stop, kill, wait, kill_cascade, pause, info)
│       │   ├── store.ex         # ETS operations for mission state
│       │   └── name.ex          # Agent name generator (adjective-noun)
│       ├── provider.ex          # Provider behaviour (build_command, parse_line, format_for_logs)
│       ├── provider/
│       │   ├── raw.ex           # Raw shell commands (wraps with sh -c)
│       │   └── claude.ex        # Claude CLI (stream-json parsing)
│       └── api_server.ex        # Unix socket API server (JSON line protocol)
├── test/
│   ├── test_helper.exs
│   ├── overmind_test.exs
│   ├── overmind/
│   │   ├── api_server_test.exs
│   │   ├── mission_test.exs
│   │   ├── mission/
│   │   │   ├── store_test.exs
│   │   │   └── name_test.exs
│   │   └── provider/
│   │       ├── raw_test.exs
│   │       └── claude_test.exs
│   └── support/                 # Test helpers (TestClaude provider, MissionHelper)
├── .claude/
│   ├── agents/
│   │   ├── scout.md             # Read-only codebase explorer
│   │   ├── code-reviewer.md     # Staff Engineer reviewer (Elixir + Shell)
│   │   └── plan-reviewer.md     # Implementation plan stress-tester
│   ├── rules/
│   │   ├── git.md               # Git conventions (commits, branches, staging)
│   │   ├── testing.md           # ExUnit/TDD conventions
│   │   ├── elixir.md            # Elixir/OTP patterns and anti-patterns
│   │   └── shell.md             # POSIX shell conventions and anti-patterns
│   └── skills/
│       ├── commit/SKILL.md      # Git commit (quick + detailed modes)
│       ├── dev/SKILL.md         # TDD implementer with agent orchestration
│       ├── review/SKILL.md      # Code review (Elixir + Shell + tech debt)
│       ├── debug/SKILL.md       # Elixir debugging workflow
│       ├── learn/SKILL.md       # Session learning extractor
│       ├── po/SKILL.md          # Product Owner (GitHub issue writer)
│       └── pr/SKILL.md          # Pull request creator
├── test_e2e.sh                  # E2E test script (daemon + raw + claude + session)
├── test_smoke.sh                # Smoke test (build, start, run, ps, shutdown)
├── mix.exs
└── CLAUDE.md
```

## Architecture

- **Shell CLI** (`bin/overmind`): POSIX shell script, sends JSON over Unix domain socket via `nc -U`
- **APIServer** (`Overmind.APIServer`): GenServer listening on `~/.overmind/overmind.sock`, dispatches JSON commands to `Overmind.*`
- **Daemon** (`Overmind.Daemon`): Starts APIServer and sleeps forever (shell script handles lifecycle)
- **Missions**: Each spawned command is a GenServer (`Mission`) under DynamicSupervisor, managing a Port. Client API in `Mission.Client`
- **Providers**: Pluggable command builders/parsers — Raw wraps with `sh -c`, Claude parses stream-json
- **ETS**: Mission state (status, logs, raw_events, name, cwd, restart_policy, restart_count, last_activity, exit_code, parent) persists after GenServer exits
- **Self-Healing**: Restart policies (`:never`, `:on_failure`, `:always`), exponential backoff, stall detection via activity timeout
- **Orchestration**: Parent hierarchy (`--parent`), `wait` (monitor-based blocking), `kill --cascade` (depth-first), `ps --tree`
- **Name Resolution**: `Store.resolve_id/1` — all public APIs accept id or agent name

## Build & Run

```bash
mix build                # compile escript binary (overmind_daemon)
sudo ln -sf "$(pwd)/bin/overmind" /usr/local/bin/overmind
overmind start           # start the daemon
overmind shutdown        # stop the daemon
mix test                 # run unit tests (auto-rebuilds escript first)
mix smoke                # smoke test (build, start daemon, run, ps, shutdown)
mix e2e                  # run E2E tests (builds, starts daemon, tests all commands)
```

`mix test` always rebuilds the escript before running tests — no stale binary risk.

## Code Standards

- Self-documenting function names; comment non-obvious logic (WHY, not WHAT)
- `mix test` must pass before committing
- `mix dialyzer` must pass before committing
- `mix smoke` must pass before committing
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

## Shell Style

### Principles
- POSIX `sh` — no bashisms (`[[ ]]`, `local`, arrays, `declare`)
- Every variable quoted: `"$var"`, `"$(cmd)"`
- `printf` for data output, `echo` only for user messages
- Small, focused functions — one responsibility each
- Descriptive names: `cmd_run`, `send_cmd`, `extract_ok`

### Structure
- Scripts <150 lines — split into sourced files under `bin/lib/`
- Helpers section at top (escape_json, send_cmd, extract_ok)
- Commands section below (cmd_start, cmd_run, cmd_ps, ...)
- Dispatch at bottom

### Safety
- `set -e` at top for fail-fast
- `trap cleanup EXIT` for temp files, sockets, child processes
- Never use `exec` in functions with traps (replaces shell, trap is lost)
- Explicit error handling: `cmd || { echo "error" >&2; return 1; }`

### Anti-patterns — DO NOT
- Unquoted variables — always `"$var"`
- `echo` for data output — use `printf '%s'`
- Monolithic scripts >150 lines — split into sourced helpers
- `exec` inside trapped functions — trap is lost
- Inline JSON construction — use helper functions
- Duplicated logic across shell functions — extract helpers

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
- **M0.5** — CWD + Names (done): `--cwd`, `--name`, auto-generated names, name resolution in all commands, refactored Socket→APIServer, CLI→Entrypoint, gutted Daemon
- **M1** — Session Agents (done): `--type session`, long-running multi-turn agents, `send`, `attach` (hybrid PTY), bidirectional stream-json
- **M2** — Self-Healing (done): restart policies (`--restart on-failure|always`), exponential backoff (`--backoff`), stall detection (`--activity-timeout`), `--max-restarts`, session resume via `--resume`, `info` command (os_pid)
- **M2.5** — Orchestration Primitives (done): `wait` (monitor-based blocking), `--parent` hierarchy, `ps --tree`, `kill --cascade`, exit code storage
- **M3** — Declarative Config: Blueprint TOML
- **M4** — Full Isolation: worktree + port allocation + Docker
- **M5** — Shared Akasha: distributed memory
- **M6** — Web Dashboard: Phoenix LiveView

For detailed roadmap see `ROADMAP.md`. Full PRD at `docs/overmind_prd.md`.

