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

```bash
mix e2e     # full E2E (daemon + raw + claude + session)
mix smoke   # quick smoke test (build, start, run, ps, shutdown)
```

`mix e2e` spawns Claude CLI via Port — this works inside Claude Code sessions because
Mission clears `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT` env vars on child processes.

## TDD Cycle

1. **RED** — Write the test asserting correct behavior, run it, confirm it fails
2. **GREEN** — Write minimum code to make it pass
3. **REFACTOR** — Clean up while staying green
4. Repeat

### Tests drive code, never the reverse

- The test defines what correct behavior is — **never change a test to match a wrong implementation**
- If the implementation returns `:stopped` but the test expects `:crashed`, fix the implementation
- When proving a branch needs coverage: remove the implementation, keep the test, watch it fail — then write the code that makes it pass
- Every `case` branch, every `_ ->` catch-all must have a test that fails without it

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
