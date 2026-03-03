---
name: review
description: Deep code review - Elixir idioms, OTP patterns, tech debt, safety. Launches 3 parallel reviewers + plan-reviewer gate. Use when: review, review this, code review, check this code, review my changes, is this good, what do you think, techdebt, tech debt, code smells.
---

# Code Review — Parallel Agents + Plan-Reviewer Gate

**Reviews current changes for correctness, idioms, tech debt, OTP safety, and shell scripting quality. Three parallel code-reviewer agents with focused scopes, aggregated findings, and a plan-reviewer critique before presenting fixes.**

## Workflow

### Phase 1: Diff

Get the full diff and diff stat against main:

```bash
git diff main...HEAD
git diff main...HEAD --stat
```

### Phase 2: Parallel Review

Launch **3 `code-reviewer` agents in parallel** (single message, 3 Agent tool calls). Each gets the full diff but a focused mandate.

**CRITICAL**: Launch all 3 agents in the **same message** so they run concurrently. Do NOT launch them sequentially.

#### Agent 1: Correctness & Safety

```
subagent_type: code-reviewer
prompt: |
  You are reviewing an Elixir/OTP + POSIX shell codebase. Focus ONLY on correctness and safety.

  ## Your scope

  ### Elixir correctness
  - Logic bugs, broken state machines, wrong ETS operations
  - GenServer callback correctness (return tuples, state transitions)
  - Port lifecycle — exit_status handling, cleanup
  - Race conditions, dead process handling
  - `Store.safe_call/2` usage for GenServer.call to possibly-dead processes
  - Raw `:ets` calls outside Store module (should use Store)
  - Missing `@impl true` on GenServer callbacks

  ### Shell safety
  - Missing `set -e` at top
  - Missing `trap cleanup EXIT` for temp files, sockets
  - `exec` inside trapped functions (replaces shell, trap lost)
  - Unquoted variables — must always be `"$var"`, `"$(cmd)"`
  - Unchecked command failures — need `cmd || { echo "error" >&2; return 1; }`
  - Exit code handling

  ### Edge cases
  - Dead processes (send to exited GenServer)
  - Missing ETS entries
  - Empty input / nil handling
  - `set -e` + `&&` short-circuit (returns exit 1 on empty val — use if/then/fi)

  ## Output format

  Return findings as a markdown list, grouped by severity:

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

  If no findings in a tier, omit that section. Be specific — cite file:line for every finding.

  ## Diff to review

  <diff>
  {PASTE FULL DIFF HERE}
  </diff>
```

#### Agent 2: Idioms & Architecture

```
subagent_type: code-reviewer
prompt: |
  You are reviewing an Elixir/OTP + POSIX shell codebase. Focus ONLY on idioms and architecture.

  ## Your scope

  ### Elixir idioms
  - `if/else` for boolean dispatch → should be multi-clause functions
  - `unless` → should be multi-clause with negated match or guard
  - Nested `case` inside `case` → extract inner match to helper
  - `cond` matching a single value → use `case` or function heads
  - `do_x(true/false)` naming → descriptive: `start_daemon(_already_running = true)`
  - Inline `if x, do: a, else: b` for nil → `maybe_x(nil)` / `maybe_x(val)` pattern
  - Single-letter vars (except iterators) → descriptive names

  ### Shell idioms
  - POSIX compliance: no `[[ ]]`, `local`, arrays, `declare`
  - `printf '%s'` for data output, `echo` only for user messages
  - Quoting: `"$var"`, `"$(cmd)"` always
  - Script size >150 lines → split into sourced files under `bin/cli/`
  - Sourced file organization and section headers

  ### Architecture
  - God modules >200 lines → extract submodules
  - DRY violations (same pattern 3+ times) → extract helper
  - N+1 ETS scans (`:ets.tab2list` then filter → `:ets.match` or `:ets.select`)
  - Over-fetching (loading all data when only a subset is needed)
  - Unnecessary abstractions (single-use wrappers)
  - Separation of concerns: CLI thin, domain in dedicated modules
  - Store isolation: all ETS ops in Store, not scattered
  - Provider behaviour: correct implementation of callbacks

  ## Output format

  Return findings as a markdown list, grouped by severity:

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

  If no findings in a tier, omit that section. Be specific — cite file:line for every finding.

  ## Diff to review

  <diff>
  {PASTE FULL DIFF HERE}
  </diff>
```

#### Agent 3: Completeness & Contracts

```
subagent_type: code-reviewer
prompt: |
  You are reviewing an Elixir/OTP + POSIX shell codebase. Focus ONLY on completeness and contracts.

  ## Your scope

  ### Documentation sync
  - Does `CLAUDE.md` "Project Structure" match the actual `lib/` and `test/` layout?
  - Are new modules, files, or features reflected in the structure section?
  - Are removed/renamed modules cleaned from the structure section?
  - Shell scripts have section headers and gotcha comments

  ### Typespecs
  - `@spec` on all public client API functions (skip private helpers)
  - `@type t :: %__MODULE__{}` on all structs
  - No `@spec` on GenServer callbacks — `@impl true` handles it
  - Correct types: `String.t()` not `string()`, `term()` not `any()`, `[type()]` not `list(type())`

  ### Test coverage
  - New public behavior has corresponding tests
  - Tests cover public API only, not private functions
  - `describe` blocks group by function/feature
  - One assertion focus per test
  - `assert_receive` with monitors preferred over `Process.sleep`
  - Shared setup extracted to `test/support/` if used across files

  ### Comments
  - Non-obvious logic has WHY comments (not WHAT)
  - No commenting obvious/self-documenting code
  - Shell gotcha comments (quoting edge cases, `set -e` interactions)

  ## Output format

  Return findings as a markdown list, grouped by severity:

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

  If no findings in a tier, omit that section. Be specific — cite file:line for every finding.

  ## Diff to review

  <diff>
  {PASTE FULL DIFF HERE}
  </diff>
```

### Phase 3: Aggregate

After all 3 agents return, merge their findings:

1. **Merge** all findings into unified tiers (Critical / Important / Minor / Positive)
2. **Deduplicate** same file:line across agents
3. **Tag** each finding with source: `[safety]`, `[idioms]`, `[completeness]`
4. **Cap**: max 5 Critical, 7 Important, 3 Minor (drop lowest-impact excess)
5. **Verdict**: any Critical or Important → "Needs fixes"; only Minor/Positive → "Clean with suggestions"

### Phase 4: Plan + Critique

**If Critical or Important findings exist:**

1. Build a numbered fix plan:
   ```
   1. [severity] file:line — proposed fix
   2. [severity] file:line — proposed fix
   ...
   ```

2. Launch a **`plan-reviewer` agent** with the fix plan and diff stat:
   ```
   subagent_type: plan-reviewer
   prompt: |
     Review this fix plan for an Elixir/OTP + POSIX shell codebase.

     ## Diff stat
     {PASTE DIFF STAT}

     ## Fix plan
     {PASTE NUMBERED FIX PLAN}

     Critique the plan:
     - Are any fixes over-engineered for the actual problem?
     - Are there gaps — issues in the diff that the plan misses?
     - Are any fixes redundant or conflicting?
     - Would any fix break existing behavior?
     - Is the priority ordering correct?

     Return:
     1. Fixes to DROP (over-engineered or unnecessary) with reasoning
     2. Fixes to ADD (gaps the plan missed) with file:line and description
     3. Fixes to MODIFY (scope adjustment) with reasoning
     4. Overall assessment: "Plan is solid" or "Plan needs adjustment"
   ```

3. **Incorporate critique**: drop over-engineered fixes, add missed gaps, adjust scope
4. Present the **critique-adjusted plan** to the user

**If only Minor findings**: skip plan-reviewer, present review directly.

### Phase 5: Present

Show the aggregated review to the user:

```markdown
## Code Review — {branch name}

**Diff**: {files changed}, {insertions}+, {deletions}-

### Critical
1) [safety] **Issue**: description
   **Location**: `file:line`
   **Fix**: solution

### Important
A) [idioms] **Issue**: description
   **Location**: `file:line`
   **Suggestion**: approach

### Minor
* [completeness] Nitpick or suggestion

### Positive
- What's done well

### Verdict
[ ] Clean - ready for `/pr`
[x] Needs fixes - see plan below

---

## Fix Plan (critique-adjusted)

1. [Critical] `file:line` — fix description
2. [Important] `file:line` — fix description
...

*Plan reviewed by plan-reviewer. Dropped N over-engineered fixes, added M gaps.*
```

### Phase 6: Implement

After user approves the plan:

1. **Enter plan mode** with the fix plan
2. Implement fixes in plan order
3. Run verification:
   ```bash
   mix test
   mix dialyzer
   mix smoke
   ```
4. Report results

## Pipeline

```
/dev <issue_url> -> /review -> /commit -> /pr
```
