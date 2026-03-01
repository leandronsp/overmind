---
name: commit
description: Create a git commit following project conventions. Use when: commit, commit this, make a commit, commit changes, git commit, save changes, commit my work, stage and commit, detailed commit.
---

# Git Commit

## Modes

### Quick (default)

Single-line commit message.

```
<type>: <short description>
```

### Detailed (`/commit detailed` or `/commit -d`)

Multi-paragraph commit for significant changes. Review the conversation and staged diff, then write:

```
<type>: <short summary>

<paragraph explaining what changed and why>

<paragraph on technical approach, trade-offs, or notable decisions>
```

Use detailed mode for: milestone features, non-obvious fixes, architectural changes, anything where "why" matters more than "what".

## Format

Types: `feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`

## Rules

1. **Concise** — short message, present tense ("add" not "added")
2. **Lowercase** after prefix
3. **No AI mentions** — never reference Claude, AI, or assistants
4. **No Co-Authored-By** — never add Co-Authored-By trailers
5. **No emojis** in commit messages
6. **Specific files** — `git add <files>`, never `git add .`

## Pre-commit Checklist

```bash
mix test
mix dialyzer
git diff --staged
```

## Examples

### Quick

```bash
git commit -m "feat: add mission genserver"
git commit -m "fix: handle port exit on crash"
git commit -m "refactor: extract ets state into module"
```

### Detailed

```bash
git commit -m "feat: add restart policies for missions

Missions can now be configured with --restart on-failure|always to
automatically restart on crash. Exponential backoff prevents tight
restart loops, starting at 1s and doubling up to the configured max.

Restart state (count, timestamps) persists in ETS across restarts
so the sliding window can enforce max-restarts limits. Logs accumulate
across restarts rather than resetting."
```
