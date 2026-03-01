---
description: Git operations — committing, branching, staging
globs: ["**/*"]
alwaysApply: false
---

# Git Conventions

## Commits

Format: `<type>: <short description>`

Types: `feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`

Rules:
- Present tense ("add" not "added"), lowercase after prefix
- Never mention AI/Claude in commits
- Never add Co-Authored-By trailers
- No emojis in commit messages

## Staging

- `git add <specific files>` — never `git add .` or `git add -A`
- Review staged diff before committing: `git diff --staged`

## Branches

- `feat/<name>` — new features
- `fix/<name>` — bug fixes
- `refactor/<name>` — refactoring
- `chore/<name>` — maintenance

## Pre-commit

```bash
mix test      # all tests pass
mix dialyzer  # no type warnings
mix smoke     # daemon lifecycle check
```

## Examples

```bash
git add lib/overmind/mission.ex test/overmind/mission_test.exs
git commit -m "feat: add mission genserver"

git add lib/overmind/mission/store.ex
git commit -m "fix: handle port exit on crash"

git add lib/overmind.ex lib/overmind/mission.ex
git commit -m "refactor: extract ets state into store module"
```
