---
name: debug
description: Elixir debugging workflow and tools. Use when: debug, debugging, pry, inspect, trace, why is this failing, what's wrong, investigate, diagnose.
---

# Debug — Elixir Debugging Workflow

## Quick Reference

### Interactive Debugging

```elixir
# IEx.pry — drops into interactive session at this point
require IEx; IEx.pry()

# Run tests with pry support
iex -S mix test test/overmind/mission_test.exs:42
```

### Tracing with IO.inspect

```elixir
# Inline inspect (returns the value, safe in pipelines)
value |> IO.inspect(label: "after_transform")

# Inspect in pipelines
data
|> parse()
|> IO.inspect(label: "parsed")
|> validate()
|> IO.inspect(label: "validated")
```

### dbg() — Pipe Debugging (Elixir 1.14+)

```elixir
# Shows each step of the pipeline
data
|> parse()
|> validate()
|> transform()
|> dbg()
```

### Targeted Test Runs

```bash
# Single file
mix test test/overmind/mission_test.exs

# Single test by line number
mix test test/overmind/mission_test.exs:42

# With trace (verbose)
mix test --trace test/overmind/mission_test.exs
```

## Daemon Debugging

```bash
# Check mission logs
overmind logs <id>

# Get mission details (os_pid, status, command)
overmind info <id>

# Check socket
ls -la ~/.overmind/overmind.sock

# Raw socket command
echo '{"command":"ps"}' | nc -U ~/.overmind/overmind.sock
```

## Process & ETS Inspection

```elixir
# Start Observer (GUI)
:observer.start()

# ETS table contents
:ets.tab2list(:overmind_missions)

# ETS lookup specific key
:ets.lookup(:overmind_missions, id)

# Process info
Process.info(pid)
Process.info(pid, [:current_function, :message_queue_len, :status])
```

## Port Debugging

```bash
# Get os_pid from overmind
overmind info <id>  # returns os_pid field

# Check if process is running
ps -p <os_pid>

# Check what the process has open
lsof -p <os_pid>

# Send signal
kill -0 <os_pid>  # check if alive (no signal sent)
```

## Common Issues

| Symptom | Check | Likely Cause |
|---------|-------|-------------|
| Mission stuck in `:running` | `overmind info <id>` | Port not exiting, stall detection not configured |
| `{:error, :not_found}` | `:ets.tab2list(:overmind_missions)` | Wrong ID, or ETS entry cleaned up |
| Socket connection refused | `ls -la ~/.overmind/overmind.sock` | Daemon not running, stale socket |
| Test timeout | `mix test --trace` | Waiting on `assert_receive` for message that never arrives |
| Dialyzer warning | `mix dialyzer` | Typespec mismatch, check return types |

## Rules

- **Never commit debug code** — no `IEx.pry`, `IO.inspect` with labels, or `dbg()` in committed code
- **Remove after use** — clean up all debug instrumentation before moving on
- **Use labels** — always label `IO.inspect` calls to distinguish multiple inspection points
- **Prefer dbg()** — for pipeline debugging, `dbg()` is cleaner than chained `IO.inspect`
