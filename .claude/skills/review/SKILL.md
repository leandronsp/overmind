---
name: review
description: Deep code review - Elixir idioms, OTP patterns, tech debt, safety. Builds a plan to address findings. Use when: review, review this, code review, check this code, review my changes, is this good, what do you think.
---

# Code Review - Elixir & OTP Expert

**Reviews current changes, runs tech debt audit, and builds a plan to address findings.**

## Workflow

1. **Diff the branch** against main to understand all changes
2. **Review** using the priorities below
3. **Run `/techdebt`** to audit for pattern deviations and code smells
4. **Enter plan mode** with a fix plan if there are Critical or Important findings
5. **Implement fixes** after user approves the plan
6. **Re-run `mix test` and `mix dialyzer`** to confirm everything is clean

If the review finds nothing actionable, skip the plan and report the verdict.

## Review Priorities

### 0. Documentation
- Does `CLAUDE.md` "Project Structure" match the actual `lib/` and `test/` layout?
- Are new modules, files, or features reflected in the structure section?
- Are removed/renamed modules cleaned from the structure section?
- Do new public functions have `@spec`?
- Do new structs have `@type t :: %__MODULE__{}`?

### 1. Correctness
- Does the logic work? (state machines, ETS operations, process lifecycle)
- Are edge cases handled? (dead processes, missing ETS entries, empty input)
- Are GenServer callbacks correct? (proper return tuples, state transitions)
- Does Port management handle exit_status and cleanup correctly?

### 2. Elixir Idioms

```elixir
# BAD: if/else for boolean dispatch
if alive?() do
  IO.puts("Running")
else
  do_start()
end

# GOOD: multi-clause functions
defp start_daemon(_already_running = true), do: IO.puts("Running")
defp start_daemon(_not_running = false), do: do_start()

# BAD: unless
unless Node.alive?() do
  Node.start(name)
end

# GOOD: multi-clause
defp maybe_start_distribution(_alive = true), do: :ok
defp maybe_start_distribution(_dead = false), do: Node.start(name)

# BAD: inline if for nil checks
events = if raw, do: events ++ [raw], else: events

# GOOD: extracted helper with pattern match
defp maybe_append(list, nil), do: list
defp maybe_append(list, event), do: list ++ [event]

# BAD: repeated ETS boilerplate
case :ets.lookup(:overmind_missions, id) do
  [{^id, pid, _, :running, _}] ->
    try do GenServer.call(pid, msg) catch :exit, _ -> fallback end
  ...
end

# GOOD: Store module abstraction
case Store.lookup(id) do
  {:running, pid, _, _} -> Store.safe_call(pid, msg)
  {:exited, _, _, _}    -> fallback
  :not_found             -> {:error, :not_found}
end
```

### 3. Safety & OTP
- No raw `:ets` calls in modules that should use Store
- `try/catch` for GenServer.call to dead processes wrapped in `Store.safe_call/2`
- `@impl true` on all GenServer callbacks
- `:temporary` restart strategy for fire-and-forget missions
- No `Process.sleep` in tests where `assert_receive` with monitors works

### 4. Architecture
- Separation of concerns (CLI thin, domain in dedicated modules)
- God modules split (<200 lines per module)
- No duplicated code across files (extract to shared helpers)
- ETS operations isolated in Store module
- Providers implement the behaviour correctly

### 5. Typespecs
- `@spec` on all public client API functions
- No `@spec` on GenServer callbacks (use `@impl true`)
- `@type t :: %__MODULE__{}` on all structs
- Correct types per CLAUDE.md reference table
- `mix dialyzer` passes with no warnings

### 6. Tests
- Tests written before or alongside implementation
- Testing public API only, not private functions
- One assertion focus per test
- `describe` blocks group by function/feature
- Shared setup extracted to `test/support/`
- `assert_receive` with monitors preferred over `Process.sleep`

## Review Output Format

```markdown
### Critical
1) **Issue**: description
   **Fix**: solution

### Important
A) **Issue**: description
   **Suggestion**: approach

### Minor
* Nitpick or suggestion

### Verdict
[ ] Clean - ready for `/pr`
[ ] Needs fixes - see plan below
```

## Checklists

### Documentation
- [ ] `CLAUDE.md` "Project Structure" matches actual layout
- [ ] New modules listed in structure
- [ ] Removed modules cleaned from structure

### Elixir Style
- [ ] No `if/else` for boolean dispatch (use multi-clause)
- [ ] No `unless` (use multi-clause with negated match)
- [ ] No nested `case` inside `case` (extract to helper)
- [ ] No inline `if` for nil checks (use `maybe_x/2` pattern)
- [ ] No god modules >200 lines
- [ ] No duplicated code across files

### OTP & Safety
- [ ] `@impl true` on all GenServer callbacks
- [ ] No raw `:ets` calls (use Store)
- [ ] Dead process calls wrapped in safe_call
- [ ] `:temporary` restart for missions
- [ ] No `Process.sleep` where monitors work

### Typespecs
- [ ] `@spec` on public client API functions
- [ ] `@type t` on all structs
- [ ] `mix dialyzer` passes
- [ ] Correct types (String.t(), term(), pid(), etc.)

### Tests
- [ ] `mix test` passes
- [ ] No testing of private functions
- [ ] `describe` blocks for grouping
- [ ] Shared setup in `test/support/`

## Pipeline

```
/tdd <issue_url> -> /review (+ /techdebt) -> /pr
```
