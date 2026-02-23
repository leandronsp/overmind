---
name: techdebt
description: Analyze current changes for potential tech debt before review or merge. Use when preparing code for review, checking for code smells, or auditing changes before PR.
---

# Tech Debt Auditor - Elixir & Overmind

## Purpose

**Staff Engineer perspective**: Catch tech debt BEFORE it reaches main. Better to flag and discuss than let debt accumulate silently.

Anything that deviates from established patterns is a **red flag**.

## What to Audit

1. Diff current branch vs main
2. Check all changed files match codebase patterns
3. Flag deviations as tech debt

```bash
git diff main...HEAD --name-only
git diff main...HEAD
```

---

## Elixir Patterns

### Critical - Control Flow

| Red Flag | Problem | Correct Pattern |
|----------|---------|-----------------|
| `if/else` for boolean dispatch | Imperative, not declarative | Multi-clause functions with pattern matching |
| `unless` | Confusing negation | Multi-clause with negated match or guard |
| Nested `case` inside `case` | Hard to read, extract | Extract inner match to a helper function |
| `cond` matching a single value | Wrong construct | Use `case` or function heads |
| `do_x(true/false)` naming | Unclear call sites | Descriptive names: `start_daemon(_already_running = true)` |
| Inline `if x, do: a, else: b` for nil | Imperative nil check | `maybe_x(nil)` / `maybe_x(val)` pattern |

```elixir
# BAD - if/else for boolean dispatch
def start do
  if alive?() do
    IO.puts("Already running")
  else
    do_start()
  end
end

# GOOD - multi-clause dispatch
def start, do: start_daemon(alive?())
defp start_daemon(_already_running = true), do: IO.puts("Already running")
defp start_daemon(_not_running = false), do: do_start()

# BAD - unless
defp ensure_distributed do
  unless Node.alive?() do
    Node.start(name, name_domain: :shortnames)
  end
end

# GOOD - multi-clause
defp ensure_distributed, do: maybe_start_distribution(Node.alive?())
defp maybe_start_distribution(_already = true), do: :ok
defp maybe_start_distribution(_needs = false), do: Node.start(name, name_domain: :shortnames)

# BAD - inline if for nil
events_acc = if raw, do: events_acc ++ [raw], else: events_acc

# GOOD - extracted helper
defp maybe_append(list, nil), do: list
defp maybe_append(list, event), do: list ++ [event]
```

### Critical - Repeated Boilerplate

| Red Flag | Problem | Correct Pattern |
|----------|---------|-----------------|
| Same ETS lookup + try/catch 3+ times | DRY violation | Extract to a Store/helper module |
| Same cleanup code in multiple places | Fragile duplication | Single `cleanup/1` function |
| Same test setup in 3+ test files | Copy-paste | Extract to `test/support/` helper |
| God modules (>200 lines) | Too many concerns | Extract submodules (e.g., Mission.Store) |

```elixir
# BAD - repeated 5 times across client functions
case :ets.lookup(:overmind_missions, id) do
  [{^id, pid, _, :running, _}] ->
    try do
      GenServer.call(pid, message)
    catch
      :exit, _ -> fallback
    end
  [{^id, _, _, _status, _}] -> ...
  [] -> {:error, :not_found}
end

# GOOD - extracted Store module, used via lookup + safe_call
case Store.lookup(id) do
  {:running, pid, _, _} -> Store.safe_call(pid, message)
  {:exited, _, _, _}    -> {:ok, Store.stored_logs(id)}
  :not_found             -> {:error, :not_found}
end
```

### Critical - Typespecs

| Red Flag | Problem | Correct Pattern |
|----------|---------|-----------------|
| Missing `@spec` on public API | No type contract | Add `@spec` on all public client functions |
| `@spec` on GenServer callbacks | Redundant, `@impl true` handles it | Remove spec, keep `@impl true` |
| `string()` instead of `String.t()` | Wrong type | Use `String.t()` for UTF-8 strings |
| `any()` instead of `term()` | Non-idiomatic | Use `term()` for unknown/generic values |
| Missing `@type t` on struct | No struct type contract | Add `@type t :: %__MODULE__{}` |
| `list(type())` instead of `[type()]` | Non-idiomatic | Use `[type()]` |

### Naming - Must Convey Intent

```elixir
# BAD - Single-letter or abbreviated variables
def handle_info({p, {:data, d}}, %{port: p} = s) do

# GOOD
def handle_info({port, {:data, data}}, %{port: port} = state) do

# BAD - Generic function names
defp do_thing(pid, msg), do: ...
defp process(id), do: ...

# GOOD - Descriptive names
defp fetch_from_process(pid, message, fallback), do: ...
defp signal_process(pid, message, error_on_dead), do: ...
```

### Architecture - Separation of Concerns

```elixir
# BAD - CLI module doing domain logic
defp cmd_run(args) do
  id = :crypto.strong_rand_bytes(4) |> Base.encode16()
  port = Port.open({:spawn, command}, [:binary])
  :ets.insert(:overmind_missions, {id, self(), command, :running})
  ...
end

# GOOD - CLI thin, domain in dedicated modules
defp cmd_run(args) do
  case execute(Overmind, :run, [command]) do
    {:ok, id} -> IO.puts("Started mission #{id}")
    {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
  end
end

# BAD - GenServer doing ETS directly
:ets.insert(:overmind_missions, {id, self(), command, :running, now})
:ets.delete(:overmind_missions, id)

# GOOD - Dedicated Store module
Store.insert(id, {self(), command, :running, now})
Store.cleanup(id)
```

---

## OTP Patterns

### Critical - Supervision & Processes

| Red Flag | Problem | Correct Pattern |
|----------|---------|-----------------|
| `Process.sleep` in tests for sync | Flaky, slow | `assert_receive` with monitors |
| Missing `@impl true` on callbacks | No compile-time check | Always use `@impl true` |
| `restart: :permanent` for tasks | Restarts crashed one-shots | `restart: :temporary` for fire-and-forget |
| Manual process cleanup | Fragile | Let supervisor handle it |
| `GenServer.call` without timeout awareness | Can hang | Consider timeouts for external calls |

```elixir
# BAD - Process.sleep for waiting
{:ok, pid} = Mission.start_link(id: id, command: "echo hello")
Process.sleep(100)
{:ok, logs} = Mission.get_logs(id)

# GOOD - Monitor for process exit
{:ok, pid} = Mission.start_link(id: id, command: "echo hello")
ref = Process.monitor(pid)
assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
{:ok, logs} = Mission.get_logs(id)
```

---

## Code Smells (AI-Generated)

### Over-commenting

```elixir
# BAD
# This function starts a mission by generating an ID,
# creating a child spec, and starting it under the supervisor
def run(command) do
  id = Mission.generate_id()
  ...
end

# GOOD - Self-documenting, no obvious comments
def run(command) do
  id = Mission.generate_id()
  ...
end
```

### Unnecessary abstraction

```elixir
# BAD - Single-use wrapper
defp validate_command(command) do
  if command == "", do: {:error, :empty_command}, else: :ok
end

# GOOD - Function head pattern match
def run("", _provider), do: {:error, :empty_command}
def run(command, provider), do: ...
```

### Defensive overkill

```elixir
# BAD - Internal code doesn't need this
def get_logs(id) when is_binary(id) and byte_size(id) > 0 do
  # id is already validated by generate_id/0...
end

# GOOD - Trust internal code, validate at boundaries
def get_logs(id) do
  case Store.lookup(id) do
    ...
  end
end
```

### Breaking established patterns

```elixir
# BAD - New pattern when codebase uses another
# Check how similar features are implemented first
# If the codebase uses Store.lookup/1 + case, don't introduce :ets.lookup directly
```

---

## TDD Compliance

| Red Flag | Problem | Correct Pattern |
|----------|---------|-----------------|
| Tests written after implementation | Not TDD | Write test BEFORE or alongside |
| Testing private functions directly | Brittle coupling | Test through public API only |
| Multiple unrelated asserts per test | Testing too many things | One assertion focus per test |
| No `describe` blocks | Unorganized tests | Group by function/feature |
| Duplicated setup across files | DRY violation | Extract to `test/support/` |
| No `mix dialyzer` before commit | Missing type safety check | Always run before committing |

---

## Output Format

```markdown
## Tech Debt Audit - [Branch Name]

### Summary
- Files changed: X
- Debt items found: N

### Critical (Must Fix)

1. **`if/else` boolean dispatch** - `lib/overmind/daemon.ex:9`
   **Issue**: Imperative control flow, should use multi-clause
   **Fix**: Extract `start_daemon(_already_running = true)` / `start_daemon(_not_running = false)`

2. **Repeated ETS boilerplate** - `lib/overmind/mission.ex:56,77,98,116,143`
   **Issue**: Same lookup + try/catch pattern 5 times
   **Fix**: Extract `Store.lookup/1` + `Store.safe_call/2`

### Should Fix

A) **Missing typespec** - `lib/overmind/foo.ex:23`
   **Issue**: Public function without `@spec`
   **Fix**: Add `@spec bar(String.t()) :: {:ok, term()} | {:error, atom()}`

B) **Duplicated test setup** - `test/overmind_test.exs`, `test/overmind/mission_test.exs`
   **Issue**: `cleanup_missions/0` copy-pasted in 3 files
   **Fix**: Extract to `test/support/mission_helper.ex`

### Consider

* Could extract magic number into module attribute
* Missing `describe` block for new test group

### Positive Notes
- Good use of pattern matching in handle_info
- Proper supervision with `:temporary` restart
- Consistent naming conventions

### Verdict
[ ] Ready for review
[ ] Needs fixes - see Critical
```

## Remember

- **Pattern deviation = red flag** — If it doesn't match codebase, flag it
- **Reference existing code** — Show where the correct pattern is used
- **Better to over-flag** — Discussion is better than silent debt
- **Run dialyzer** — `mix dialyzer` catches type issues
- **Check the tables above** — Common issues specific to Elixir/OTP/Overmind
- **Consult CLAUDE.md** — Anti-patterns and style rules are the source of truth
