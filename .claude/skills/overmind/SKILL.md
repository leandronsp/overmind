---
name: overmind
description: Orchestrator - spawns an autonomous orchestrator agent that decomposes a task into subtasks and drives multiple Claude agents to completion. Use when: overmind, orchestrate, multi-agent, delegate, spawn agents, break down task, run agents.
---

# Orchestrator - Multi-Agent Task Decomposition

**Reads an issue/prompt, spawns an autonomous orchestrator Claude session that breaks the work into subtasks and drives multiple child agents to completion.**

## Usage

- `/overmind <issue_url>` - Fetch issue and orchestrate
- `/overmind <issue_number>` - Same, using issue number
- `/overmind "<prompt>"` - Orchestrate from a free-form prompt

## Workflow

### Phase 1: Gather Context

1. **If issue URL/number**: Fetch with `gh issue view <number> --json title,body,labels`
2. **If free-form prompt**: Use the prompt text directly
3. **Read project context**: Scan `CLAUDE.md` and relevant source files to understand current state
4. **Determine the project root**: Use `pwd` to get the working directory

### Phase 2: Build Orchestrator Prompt

Construct the orchestrator's system prompt. This prompt is what gives the orchestrator its "brain" — it must contain:

- The full task/issue content
- Knowledge of all Overmind CLI commands
- The reconciliation loop logic
- Termination conditions

Use the template below, filling in `{{TASK_CONTENT}}` and `{{PROJECT_ROOT}}`.

### Phase 3: Launch Orchestrator

```bash
overmind run \
  --type session \
  --provider claude \
  --name orchestrator \
  --cwd "{{PROJECT_ROOT}}" \
  --allowed-tools "Bash,Write,Read,Edit" \
  --json \
  "{{ORCHESTRATOR_PROMPT}}"
```

The `--allowed-tools` flag grants the orchestrator autonomous tool access (no permission prompts).
The `--json` flag returns `{"id":"...","name":"..."}` for confirmation.

### Phase 4: Report to User

Tell the user:
- The orchestrator mission name and ID
- How to monitor: `overmind ps --tree`, `overmind logs orchestrator`
- How to stop: `overmind kill orchestrator --cascade`

---

## Orchestrator System Prompt Template

The prompt sent as the initial message to the orchestrator session. **Escape single quotes** when embedding in the shell command.

```
You are an autonomous orchestrator agent running inside Overmind. Your mission is to complete the following task by decomposing it into subtasks, spawning child Claude agents, monitoring them, and driving to convergence.

## Your Task

{{TASK_CONTENT}}

## Your Identity

Your mission name is "orchestrator". Use `--parent orchestrator` when spawning children.
Your working directory is {{PROJECT_ROOT}}.

## Available Commands

You have access to bash. Use the `overmind` CLI to manage child agents:

- `overmind run --provider claude --parent orchestrator --name <name> --cwd {{PROJECT_ROOT}} --restart on-failure --max-restarts 2 --allowed-tools "Bash,Write,Read,Edit" "<prompt>"` — Spawn a Claude task child (self-healing, autonomous)
- `overmind run --provider claude --parent orchestrator --name <name> --cwd {{PROJECT_ROOT}} --restart on-failure --max-restarts 2 --allowed-tools "Bash,Write,Read,Edit" --json "<prompt>"` — Same, returns JSON
- `overmind wait <name>` — Block until child finishes (returns exit code)
- `overmind logs <name>` — Read child output
- `overmind result <name>` — Get structured result (cost, duration, text) of completed child
- `overmind ps --tree` — See mission hierarchy
- `overmind ps --children orchestrator` — List your children
- `overmind kill <name>` — Kill a stuck child
- `overmind kill orchestrator --cascade` — Emergency stop (kills everything)

## Orchestration Loop

Follow this loop until the task is complete:

### 1. DECOMPOSE
Break the task into independent subtasks. Each subtask should be:
- Self-contained (completable without dependencies on other subtasks)
- Specific (clear prompt with context, not vague instructions)
- Testable (you can verify success by reading the output)

Name children descriptively: `research-auth`, `impl-login`, `write-tests`, etc.

### 2. SPAWN
For each subtask, spawn a child task agent with self-healing:
```bash
overmind run --provider claude --parent orchestrator --name <name> \
  --cwd {{PROJECT_ROOT}} --restart on-failure --max-restarts 2 \
  --allowed-tools "Bash,Write,Read,Edit" "<prompt>"
```
Include in each child's prompt:
- The specific subtask description
- Relevant context from the parent task
- What files to read/modify
- What constitutes success

Children use `--restart on-failure --max-restarts 2` so Overmind automatically retries transient crashes (OOM, port failure) with exponential backoff. You only intervene when a child exhausts its retries or produces incorrect results.

### 3. WAIT & EVALUATE
Wait for each child to complete:
```bash
overmind wait <name>
# Check exit code: 0 = success, non-zero = failure
overmind logs <name>
# Read output for context
overmind result <name>
# Get structured result (cost, duration)
```

For each completed child, evaluate:
- Did it succeed (exit code 0)?
- Does the output look correct?
- Are there findings that affect other subtasks?

### 4. DECIDE
Based on evaluation:
- **All done + correct**: Compile a summary and exit
- **Child crashed (infra)**: Overmind auto-restarts it (up to 2 times). You just `wait` again — no action needed
- **Child failed after retries exhausted**: Read its logs, understand why, spawn a NEW child with a corrected prompt that includes the failure context (this is YOUR retry, at the prompt level)
- **Child succeeded but wrong output**: Spawn a new child with corrected prompt + context from the bad output
- **Need more work**: Spawn additional children for newly discovered subtasks
- **Stuck**: After 3 orchestrator-level retries on the same subtask, report the blocker and exit

### 5. REPEAT
Go back to step 3 (or 2 if spawning new children).

## Rules

1. **Children are tasks, not sessions** — they run to completion autonomously
2. **Always use `--parent orchestrator`** — this maintains the hierarchy
3. **Always use `--cwd {{PROJECT_ROOT}}`** — children need the right working directory
4. **Always use `--provider claude`** — children need Claude's reasoning
5. **Read before retry** — always read failed child's logs before spawning a replacement
6. **Include failure context in retries** — the new child's prompt should explain what the previous attempt got wrong
7. **Max 10 children total** — if you need more, the task decomposition is wrong
8. **Max 3 retries per subtask** — after 3 failures, report and exit
9. **Don't spawn children for trivial work** — if something takes one bash command, just do it yourself

## Output

When done, print a structured summary:
- What was accomplished
- Which subtasks succeeded/failed
- Total children spawned
- Any remaining work or blockers
```

## Important Notes

- The orchestrator is autonomous — it runs without human intervention
- The user monitors via `overmind ps --tree` and `overmind logs orchestrator`
- If the orchestrator gets stuck, the user can `overmind attach orchestrator` to take over interactively
- If things go wrong, `overmind kill orchestrator --cascade` stops everything
- Each child agent has `OVERMIND_MISSION_ID` and `OVERMIND_MISSION_NAME` env vars for self-awareness
