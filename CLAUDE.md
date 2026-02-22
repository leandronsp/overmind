# Overmind

Kubernetes for AI Agents. Local-first runtime that treats AI agents as supervised processes.

## Stack

- **Elixir** — OTP supervision, GenServer, ETS
- **Mix** — build tool, escript for CLI binary
- **No Phoenix** until M6 (web dashboard)

## Project Structure

```
├── lib/
│   ├── overmind.ex              # Root module
│   └── overmind/
│       ├── application.ex       # OTP Application
│       └── cli.ex               # Escript entry point
├── test/
│   ├── test_helper.exs
│   └── overmind_test.exs
├── mix.exs
└── CLAUDE.md
```

## Build & Run

```bash
mix build            # compile escript binary (alias for mix escript.build)
./overmind           # run CLI
mix test             # run tests (auto-rebuilds escript first)
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

- **M0** — Spawn & Observe (current): `run`, `ps`, `logs`, `stop`, `kill`
- **M1** — Human-in-the-Loop: `send`, `attach`
- **M2** — Self-Healing: restart policies, backoff
- **M3** — Declarative Config: Blueprint TOML
- **M4** — Full Isolation: worktree + port allocation + Docker
- **M5** — Shared Akasha: distributed memory
- **M6** — Web Dashboard: Phoenix LiveView

For detailed roadmap see `ROADMAP.md`. Full PRD at `docs/overmind_prd.md`.

