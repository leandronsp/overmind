---
name: learn
description: Extract learnings from the current session and update memory/config. Use when: learn from this, what did we learn, update memory, session retrospective, extract patterns, save learnings.
---

# Session Learning Extractor

**Scans the current session for patterns, corrections, and feedback, then proposes updates to memory and config.**

## Usage

- `/learn` — Scan session, propose updates
- `/learn <topic>` — Focus extraction on a specific topic

## Workflow

### Phase 1: Scan Session

Review the conversation for:

1. **PR review feedback** — corrections, style preferences, pattern violations flagged
2. **Errors encountered** — what went wrong, what fixed it, root cause
3. **Patterns discovered** — new conventions, architectural decisions, workflow preferences
4. **Corrections** — things the user corrected (naming, approach, style)
5. **Explicit instructions** — "always do X", "never do Y", "remember this"

### Phase 2: Compare Against Config

Check each learning against existing config layers:

| Layer | Path | Purpose |
|-------|------|---------|
| CLAUDE.md | `./CLAUDE.md` | Project conventions (checked in) |
| Rules | `.claude/rules/*.md` | Contextual rules (loaded by glob/description) |
| Agents | `.claude/agents/*.md` | Agent personalities and strategies |
| Skills | `.claude/skills/*/SKILL.md` | Skill definitions |
| Memory | `~/.claude/projects/.../memory/` | Persistent cross-session memory |

### Phase 3: Identify Gaps

For each learning, classify:

- **Missing** — not captured anywhere, needs to be added
- **Contradicts** — conflicts with existing rule/memory
- **Vague** — existing rule is too general, needs sharpening
- **Wrong layer** — captured but in the wrong place (e.g., session-specific in CLAUDE.md)
- **Already covered** — no action needed

### Phase 4: Propose Updates

Present findings grouped by target file:

```markdown
## Session Learnings

### New Patterns Found
1. [pattern]: [evidence from session]

### Proposed Updates

#### memory/MEMORY.md
- Add: [new entry]
- Update: [existing entry] → [revised entry]

#### .claude/rules/elixir.md
- Add: [new rule with evidence]

#### CLAUDE.md
- Update: [section] — [what changed and why]

### No Action Needed
- [learning already covered by existing config]
```

## Rules

- **Evidence-based** — every proposed update must reference a specific moment in the session
- **Right layer** — session-specific → memory, stable patterns → rules, project conventions → CLAUDE.md
- **No duplicates** — check existing content before proposing additions
- **Worktree-aware** — always write to main tree's memory path, not worktree
- **Confirm before writing** — present proposals, wait for user approval before modifying any file
- **Concise memory** — MEMORY.md must stay under 200 lines (truncated beyond that)
