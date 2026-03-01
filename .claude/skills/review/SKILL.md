---
name: review
description: Deep code review - Elixir idioms, OTP patterns, tech debt, safety. Builds a plan to address findings. Use when: review, review this, code review, check this code, review my changes, is this good, what do you think, techdebt, tech debt, code smells.
---

# Code Review — Elixir/OTP & Shell Expert

**Reviews current changes for correctness, idioms, tech debt, OTP safety, and shell scripting quality. Builds a fix plan for findings.**

## Workflow

1. **Diff the branch** against main to understand all changes
2. **Review** using the priorities below (includes tech debt audit)
3. **Enter plan mode** with a fix plan if there are Critical or Important findings
4. **Implement fixes** after user approves the plan
5. **Re-run `mix test`, `mix dialyzer`, and `mix smoke`** to confirm everything is clean

If the review finds nothing actionable, skip the plan and report the verdict.

## Review Priorities

### 0. Documentation
- Does `CLAUDE.md` "Project Structure" match the actual `lib/` and `test/` layout?
- Are new modules, files, or features reflected in the structure section?
- Are removed/renamed modules cleaned from the structure section?
- Do new public functions have `@spec`?
- Do new structs have `@type t :: %__MODULE__{}`?
- Non-obvious logic has explanatory comments (WHY, not WHAT)
- Shell scripts have section headers and gotcha comments

### 1. Correctness
- Does the logic work? (state machines, ETS operations, process lifecycle)
- Are edge cases handled? (dead processes, missing ETS entries, empty input)
- Are GenServer callbacks correct? (proper return tuples, state transitions)
- Does Port management handle exit_status and cleanup correctly?

### 2. Elixir Idioms & Tech Debt

#### Control Flow

| Red Flag | Correct Pattern |
|----------|-----------------|
| `if/else` for boolean dispatch | Multi-clause functions with pattern matching |
| `unless` | Multi-clause with negated match or guard |
| Nested `case` inside `case` | Extract inner match to a helper function |
| `cond` matching a single value | `case` or function heads |
| `do_x(true/false)` naming | Descriptive: `start_daemon(_already_running = true)` |
| Inline `if x, do: a, else: b` for nil | `maybe_x(nil)` / `maybe_x(val)` pattern |

```elixir
# BAD
if alive?() do
  IO.puts("Running")
else
  do_start()
end

# GOOD
defp start_daemon(_already_running = true), do: IO.puts("Running")
defp start_daemon(_not_running = false), do: do_start()

# BAD
events = if raw, do: events ++ [raw], else: events

# GOOD
defp maybe_append(list, nil), do: list
defp maybe_append(list, event), do: list ++ [event]
```

#### Boilerplate & DRY

| Red Flag | Correct Pattern |
|----------|-----------------|
| Same ETS lookup + try/catch 3+ times | Extract to Store/helper module |
| Same cleanup code in multiple places | Single `cleanup/1` function |
| Same test setup in 3+ test files | Extract to `test/support/` helper |
| God modules (>200 lines) | Extract submodules |

#### Naming

```elixir
# BAD
def handle_info({p, {:data, d}}, %{port: p} = s) do

# GOOD
def handle_info({port, {:data, data}}, %{port: port} = state) do
```

#### Code Smells

- Commenting obvious code (self-documenting names need no narration)
- Missing comments on non-obvious logic, gotchas, or protocol details
- Single-use wrapper functions (unnecessary abstraction)
- Defensive guards on internal code
- Breaking established codebase patterns

### 3. Shell Idioms & Tech Debt

#### Structure

| Red Flag | Correct Pattern |
|----------|-----------------|
| Monolithic script >150 lines | Split into sourced files under `bin/lib/` |
| Duplicated logic across functions | Extract shared helpers (`escape_json`, `send_cmd`) |
| Inline JSON building everywhere | Helper function for JSON construction |
| Giant `case` dispatch at bottom | Clean `cmd_*` functions, dispatch table |

#### POSIX Compliance

| Red Flag | Correct Pattern |
|----------|-----------------|
| `[[ ]]` double brackets | `[ ]` single brackets |
| `local` keyword | No `local` in POSIX sh (use subshell or naming convention) |
| `echo` for data | `printf '%s' "$val"` for portability |
| Unquoted `$var` | Always `"$var"`, `"$(cmd)"` |
| Bashisms (arrays, `declare`) | POSIX alternatives |

#### Safety

| Red Flag | Correct Pattern |
|----------|-----------------|
| Missing `set -e` | Always `set -e` at top |
| No `trap` cleanup | `trap cleanup EXIT` for temp files, sockets |
| `exec` in trapped functions | Regular invocation (exec replaces shell, trap lost) |
| Unchecked command failures | `cmd || { echo "error" >&2; return 1; }` |
| Missing quotes around paths | `"$SOCK"`, `"$PIDFILE"` — always quote |

```sh
# BAD — monolithic, unquoted, no cleanup
start() {
  nohup $DAEMON > $LOG 2>&1 &
  pid=$!
  # 50 more lines...
}

# GOOD — modular, quoted, proper cleanup
cmd_start() {
  if [ -S "$SOCK" ]; then
    echo "Already running"
    return 0
  fi
  mkdir -p "$(dirname "$SOCK")"
  nohup "$DAEMON" __daemon__ > "$LOGFILE" 2>&1 &
  echo "$!" > "$PIDFILE"
}
```

### 4. Safety & OTP
- No raw `:ets` calls in modules that should use Store
- `try/catch` for GenServer.call to dead processes wrapped in `Store.safe_call/2`
- `@impl true` on all GenServer callbacks
- `:temporary` restart strategy for fire-and-forget missions
- No `Process.sleep` in tests where `assert_receive` with monitors works

### 5. Architecture
- Separation of concerns (CLI thin, domain in dedicated modules)
- Elixir god modules split (<200 lines per module)
- Shell scripts split (<150 lines per file, sourced helpers in `bin/lib/`)
- No duplicated code across files (extract to shared helpers)
- ETS operations isolated in Store module
- Providers implement the behaviour correctly

### 6. Typespecs

| Red Flag | Correct Pattern |
|----------|-----------------|
| Missing `@spec` on public API | Add `@spec` on all public client functions |
| `@spec` on GenServer callbacks | Remove spec, keep `@impl true` |
| `string()` | `String.t()` |
| `any()` | `term()` |
| Missing `@type t` on struct | Add `@type t :: %__MODULE__{}` |
| `list(type())` | `[type()]` |

### 7. Tests
- Tests written before or alongside implementation
- Testing public API only, not private functions
- One assertion focus per test
- `describe` blocks group by function/feature
- Shared setup extracted to `test/support/`
- `assert_receive` with monitors preferred over `Process.sleep`
- E2E tests (`test_e2e.sh`) for shell CLI integration

## Review Output Format

```markdown
### Critical
1) **Issue**: description
   **Location**: `file:line`
   **Fix**: solution

### Important
A) **Issue**: description
   **Location**: `file:line`
   **Suggestion**: approach

### Minor
* Nitpick or suggestion

### Positive
- What's done well

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
- [ ] Descriptive variable names (no single-letter except iterators)

### Shell
- [ ] POSIX `sh` compatible (no bashisms)
- [ ] All variables quoted (`"$var"`)
- [ ] `printf` for data output (not `echo`)
- [ ] Scripts <150 lines (split into `bin/lib/`)
- [ ] No duplicated logic across functions
- [ ] `set -e` at top
- [ ] `trap` cleanup for temp resources
- [ ] No `exec` in trapped functions
- [ ] Descriptive function names (`cmd_*` pattern)

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
- [ ] `mix smoke` passes
- [ ] No testing of private functions
- [ ] `describe` blocks for grouping
- [ ] Shared setup in `test/support/`

## Pipeline

```
/dev <issue_url> -> /review -> /commit -> /pr
```
