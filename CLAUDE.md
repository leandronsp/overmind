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
mix escript.build    # compile binary
./overmind           # run CLI
mix test             # run tests
```

## Code Standards

- Self-documenting function names, minimal comments
- `mix test` must pass before committing
- `mix dialyzer` must pass before committing
- No external deps unless strictly necessary

## Typespecs

Typespecs serve as deterministic constraints on LLM-generated code — the type checker rejects invalid output the same way a compiler rejects syntax errors.

- `@type t` on every struct
- `@spec` on all public functions (skip private helpers)
- GenServer callbacks: always spec return tuples explicitly
- Skip specs on CLI glue code and test helpers

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

