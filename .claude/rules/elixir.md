---
description: Elixir/OTP patterns, idioms, and anti-patterns
globs: ["lib/**/*.ex", "test/**/*.exs"]
alwaysApply: false
---

# Elixir/OTP Patterns

## Control Flow

- **Multi-clause functions** over `if/else` for boolean dispatch
- **No `unless`** — use multi-clause with negated match or guard
- **`case`** only for matching an already-computed value
- **`maybe_x(nil)` / `maybe_x(val)`** pattern for optional values
- **No nested `case` inside `case`** — extract inner match to a helper
- Named boolean dispatch: `start_daemon(_already_running = true)`

```elixir
# GOOD
defp maybe_append(list, nil), do: list
defp maybe_append(list, event), do: list ++ [event]

# BAD
events = if raw, do: events ++ [raw], else: events
```

## OTP

- `@impl true` on all GenServer callbacks
- `:temporary` restart for fire-and-forget missions
- Store module for all ETS operations — no raw `:ets` calls in business logic
- `Store.safe_call/2` wraps `GenServer.call` with `try/catch` for dead processes
- Let supervisors handle process cleanup

## Typespecs

- `@spec` on all public client API functions
- `@type t :: %__MODULE__{}` on all structs
- Skip `@spec` on GenServer callbacks — `@impl true` handles it
- Skip specs on CLI glue code and test helpers

Type reference:
- `String.t()` (not `string()`), `binary()` for raw bytes
- `pid()`, `port()`, `atom()`, `boolean()`
- `integer()`, `non_neg_integer()`
- `term()` (not `any()`)
- `[type()]` (not `list(type())`)
- `GenServer.on_start()`, `DynamicSupervisor.on_start_child()`

## Naming

- Descriptive variable names, no single-letter vars except iterators
- Domain-driven naming: types over primitives
- Modules <200 lines — extract submodules when growing

## Comments

- Comment non-obvious logic, gotchas, and protocol details
- Don't comment self-documenting functions (obvious names, simple patterns)
- Explain WHY, not WHAT — the code shows what, comments explain intent
- Section headers (`# Port management`, `# Restart logic`) help navigate large files

## Architecture

- Thin CLI, domain logic in dedicated modules
- ETS operations isolated in Store
- Providers implement the behaviour (`build_command`, `parse_line`, `format_for_logs`)
- No duplicated code across files — extract shared helpers

## Anti-Patterns

- `if/else` for boolean dispatch
- `unless` anywhere
- Nested `case` inside `case`
- `cond` matching a single value
- `do_something(true/false)` naming
- Inline `if x, do: a, else: b` for nil checks
- God modules >200 lines
- Raw `:ets` calls outside Store
- `Process.sleep` in tests
- Commenting obvious code (self-documenting names need no narration)
- Defensive guards on internal code
