---
description: ExUnit testing and TDD conventions
globs: ["test/**/*", "lib/**/*"]
alwaysApply: false
---

# Testing Conventions

## Running Tests

```bash
mix test                              # all unit tests
mix test test/overmind/mission_test.exs  # single file
mix test test/overmind/mission_test.exs:42  # single test by line
mix dialyzer                          # type checking (typespecs are tests too)
mix smoke                             # daemon lifecycle (build, start, run, ps, shutdown)
```

## E2E Testing

**NEVER run `mix e2e`** — it spawns Claude CLI which cannot run inside a Claude session.

Instead, run the smoke test after shell or integration changes:

```bash
mix smoke
```

This builds the escript, starts the daemon, runs a command, checks ps, and shuts down. Tell the user to run `mix e2e` themselves for full coverage.

## TDD Cycle

1. **RED** — Write one failing test for the next behavior
2. **GREEN** — Write minimum code to make it pass
3. **REFACTOR** — Clean up while staying green
4. Repeat

## Conventions

- Write tests BEFORE or alongside implementation, never after
- Test public API only — never test private functions
- One assertion focus per test (multiple asserts OK if one logical thing)
- `describe` blocks to group by function/feature
- Shared setup in `test/support/` if used across files

## Async & Process Testing

```elixir
# GOOD — monitor for process exit
{:ok, pid} = Mission.start_link(opts)
ref = Process.monitor(pid)
assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

# BAD — sleeping and hoping
Process.sleep(100)
assert Mission.get_status(id) == :exited
```

Always prefer `assert_receive` with monitors over `Process.sleep`.

## Edge Cases to Test

- `nil` input
- Empty strings / empty lists
- Dead processes (send to exited GenServer)
- Missing ETS entries
- Concurrent access patterns
