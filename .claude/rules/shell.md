---
description: POSIX shell conventions and anti-patterns
globs: ["bin/**/*"]
alwaysApply: false
---

# Shell Conventions

## Principles

- POSIX `sh` — no bashisms (`[[ ]]`, `local`, arrays, `declare`)
- Every variable quoted: `"$var"`, `"$(cmd)"`
- `printf` for data output, `echo` only for user messages
- Small, focused functions — one responsibility each
- Descriptive names: `cmd_run`, `send_cmd`, `extract_ok`

## Structure

- Scripts <150 lines — split into sourced files under `bin/cli/`
- Helpers section at top (escape_json, send_cmd, extract_ok)
- Commands section below (cmd_start, cmd_run, cmd_ps, ...)
- Dispatch at bottom

## Safety

- `set -e` at top for fail-fast
- `trap cleanup EXIT` for temp files, sockets, child processes
- Never use `exec` in functions with traps (replaces shell, trap is lost)
- Explicit error handling: `cmd || { echo "error" >&2; return 1; }`

## Comments

- Header comment on each sourced file explaining its role
- Comment non-obvious sed/awk pipelines and their purpose
- Comment timing-sensitive loops (poll intervals, why those durations)
- Comment gotchas: `set -e` interactions, exit code traps, quoting edge cases
- Section comments to group related functions

## Anti-Patterns

- Unquoted variables — always `"$var"`
- `echo` for data output — use `printf '%s'`
- Monolithic scripts >150 lines — split into sourced helpers
- `exec` inside trapped functions — trap is lost
- Inline JSON construction — use helper functions
- Duplicated logic across shell functions — extract helpers
- `[ -n "$val" ] && printf ...` with `set -e` — use `if/then/fi` (short-circuit returns exit 1 on empty val)
