#!/bin/sh
# Overmind CLI commands — user-facing cmd_* functions dispatched by bin/overmind.
# Each function builds JSON, sends it over the Unix socket, and formats output.
# Daemon lifecycle commands live in daemon.sh.

cmd_run() {
  command=""
  type="task"
  provider="raw"
  cwd=""
  name=""
  parent=""
  restart=""
  max_restarts=""
  max_seconds=""
  backoff=""
  activity_timeout=""
  allowed_tools=""
  json_output=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --type)             type="$2"; shift 2 ;;
      --provider)         provider="$2"; shift 2 ;;
      --cwd)              cwd="$2"; shift 2 ;;
      --name)             name="$2"; shift 2 ;;
      --parent)           parent="$2"; shift 2 ;;
      --restart)          restart="$2"; shift 2 ;;
      --max-restarts)     max_restarts="$2"; shift 2 ;;
      --max-seconds)      max_seconds="$2"; shift 2 ;;
      --backoff)          backoff="$2"; shift 2 ;;
      --activity-timeout) activity_timeout="$2"; shift 2 ;;
      --allowed-tools)    allowed_tools="$2"; shift 2 ;;
      --json)             json_output="true"; shift ;;
      *)                  command="$command $1"; shift ;;
    esac
  done
  # Non-flag args accumulate with leading space; strip it
  command=$(printf '%s' "$command" | sed 's/^ //')

  if [ -z "$command" ] && [ "$type" = "task" ]; then
    echo "Missing command. Usage: overmind run <command>"
    return 1
  fi

  escaped=$(escape_json "$command")
  # Build optional JSON fields — each maybe_json_* returns empty string if val is empty
  extra=""
  extra="$extra$(maybe_json_str "cwd" "$cwd")"
  extra="$extra$(maybe_json_str "name" "$name")"
  extra="$extra$(maybe_json_str "parent" "$parent")"
  extra="$extra$(maybe_json_str "restart" "$restart")"
  extra="$extra$(maybe_json_int "max_restarts" "$max_restarts")"
  extra="$extra$(maybe_json_int "max_seconds" "$max_seconds")"
  extra="$extra$(maybe_json_int "backoff" "$backoff")"
  extra="$extra$(maybe_json_int "activity_timeout" "$activity_timeout")"
  extra="$extra$(maybe_json_str "allowed_tools" "$allowed_tools")"

  json="{\"cmd\":\"run\",\"args\":{\"command\":\"$escaped\",\"type\":\"$type\",\"provider\":\"$provider\"$extra}}"
  response=$(send_cmd "$json") || return 1

  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  # Response: {"ok":{"id":"...","name":"..."}}
  id=$(printf '%s' "$response" | sed 's/.*"id":"\([^"]*\)".*/\1/')
  run_name=$(printf '%s' "$response" | sed 's/.*"name":"\([^"]*\)".*/\1/')

  if [ "${json_output:-}" = "true" ]; then
    printf '{"id":"%s","name":"%s"}\n' "$id" "$run_name"
  else
    echo "Started mission $id ($run_name)"
  fi
}

cmd_claude_run() {
  if [ $# -eq 0 ]; then
    echo "Missing prompt. Usage: overmind claude run <prompt>"
    return 1
  fi
  cmd_run --provider claude "$@"
}

cmd_ps() {
  tree=""
  children=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --tree)     tree="true"; shift ;;
      --children) children="$2"; shift 2 ;;
      *)          shift ;;
    esac
  done

  if [ -n "$children" ]; then
    escaped=$(escape_json "$children")
    json="{\"cmd\":\"ps\",\"args\":{\"children\":\"$escaped\"}}"
  elif [ -n "$tree" ]; then
    json='{"cmd":"ps","args":{"tree":true}}'
  else
    json='{"cmd":"ps"}'
  fi

  response=$(send_cmd "$json") || return 1
  text=$(extract_ok "$response") || return 1
  unescape_json "$text"
}

cmd_info() {
  escaped=$(escape_json "$1")
  response=$(send_cmd "{\"cmd\":\"info\",\"args\":{\"id\":\"$escaped\"}}") || return 1
  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi
  inner=$(printf '%s' "$response" | sed 's/^{"ok"://' | sed 's/}$//')
  if [ "$inner" = "{" ]; then
    printf '{}\n'
  else
    printf '%s\n' "$inner"
  fi
}

cmd_logs() {
  escaped=$(escape_json "$1")
  response=$(send_cmd "{\"cmd\":\"logs\",\"args\":{\"id\":\"$escaped\"}}") || return 1
  text=$(extract_ok "$response") || return 1
  unescape_json "$text"
}

cmd_result() {
  escaped=$(escape_json "$1")
  response=$(send_cmd "{\"cmd\":\"result\",\"args\":{\"id\":\"$escaped\"}}") || return 1

  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  # Response: {"ok":{"type":"result","result":"...","cost_usd":N,...}} or {"ok":{}}
  inner=$(printf '%s' "$response" | sed 's/^{"ok"://' | sed 's/}$//')
  if [ "$inner" = "{" ]; then
    printf '{}\n'
  else
    printf '%s\n' "$inner"
  fi
}

cmd_stop() { simple_id_cmd "stop" "$1" "Stopped"; }
cmd_kill() {
  id=""
  cascade=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --cascade) cascade="true"; shift ;;
      *)         id="$1"; shift ;;
    esac
  done

  if [ -z "$id" ]; then
    echo "Missing id. Usage: overmind kill <id> [--cascade]"
    return 1
  fi

  escaped=$(escape_json "$id")

  if [ -n "$cascade" ]; then
    response=$(send_cmd "{\"cmd\":\"kill\",\"args\":{\"id\":\"$escaped\",\"cascade\":true}}") || return 1
    extract_ok "$response" > /dev/null || return 1
    echo "Killed mission $id and all children"
  else
    simple_id_cmd "kill" "$id" "Killed"
  fi
}

cmd_send() {
  id="$1"
  shift
  message="$*"
  eid=$(escape_json "$id")
  emsg=$(escape_json "$message")
  response=$(send_cmd "{\"cmd\":\"send\",\"args\":{\"id\":\"$eid\",\"message\":\"$emsg\"}}") || return 1
  extract_ok "$response" > /dev/null || return 1
  echo "Sent to mission $id"
}

cmd_detach() { simple_id_cmd "unpause" "$1" "Detached from"; }

cmd_tui() {
  if [ ! -S "$SOCK" ]; then
    echo "Daemon not running. Start with: overmind start" >&2
    return 1
  fi
  # Safety net: restore terminal if the escript crashes before it can clean up
  trap 'stty sane 2>/dev/null; printf "\n"' EXIT
  "$DAEMON" __tui__
}

cmd_attach() {
  id="$1"
  escaped=$(escape_json "$id")
  response=$(send_cmd "{\"cmd\":\"pause\",\"args\":{\"id\":\"$escaped\"}}") || return 1

  # Error check before field parsing — pause response has nested JSON
  # that extract_ok can't handle, so we parse manually with sed
  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  # Response: {"ok":{"session_id":"...","cwd":"..."}} or {"ok":{"session_id":null,"cwd":null}}
  # sed won't match unquoted null values — grep first to detect quoted strings
  session_id=""
  if printf '%s' "$response" | grep -q '"session_id":"'; then
    session_id=$(printf '%s' "$response" | sed 's/.*"session_id":"\([^"]*\)".*/\1/')
  fi
  cwd=""
  if printf '%s' "$response" | grep -q '"cwd":"'; then
    cwd=$(printf '%s' "$response" | sed 's/.*"cwd":"\([^"]*\)".*/\1/')
  fi

  # No session yet (first prompt hasn't been sent) — unpause and bail
  if [ "$session_id" = "null" ] || [ -z "$session_id" ]; then
    printf '{\"cmd\":\"unpause\",\"args\":{\"id\":\"%s\"}}\n' "$escaped" | nc -U "$SOCK" > /dev/null 2>&1
    echo "Mission $id has no session ID yet"
    return 1
  fi

  # Unpause on ALL exit paths: Ctrl+C, Claude crash, normal exit
  _cleanup_attach() {
    printf '{"cmd":"unpause","args":{"id":"%s"}}\n' "$escaped" | nc -U "$SOCK" > /dev/null 2>&1
  }
  trap _cleanup_attach EXIT

  # Claude session must run in the mission's CWD for --resume to find its state
  if [ -n "$cwd" ] && [ "$cwd" != "null" ]; then
    cd "$cwd" || true
  fi

  claude --resume "$session_id"
}

cmd_apply() {
  if [ -z "${1:-}" ]; then
    echo "Missing file. Usage: overmind apply <file.toml>"
    return 1
  fi
  path="$1"
  # Resolve to absolute path before sending to daemon (daemon's CWD may differ)
  if [ -f "$path" ]; then
    path="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  fi
  escaped=$(escape_json "$path")
  response=$(send_cmd "{\"cmd\":\"apply\",\"args\":{\"path\":\"$escaped\"}}") || return 1
  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi
  text=$(extract_ok "$response") || return 1
  echo "Blueprint applied:"
  printf '%s\n' "$text" | tr ',' '\n' | sed 's/[{}]//g; s/"name"://g; s/"id"://g; s/"//g; s/^ //; /^$/d'
}

cmd_agents() {
  if [ -z "${1:-}" ]; then
    echo "Missing file. Usage: overmind agents <file.toml>"
    return 1
  fi
  path="$1"
  if [ -f "$path" ]; then
    path="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  fi
  escaped=$(escape_json "$path")
  response=$(send_cmd "{\"cmd\":\"agents\",\"args\":{\"path\":\"$escaped\"}}") || return 1
  text=$(extract_ok "$response") || return 1
  unescape_json "$text"
}

cmd_isolate() {
  project_path="${1:-$(pwd)}"
  mission_id="${2:-}"

  if [ -z "$mission_id" ]; then
    echo "Missing mission id. Usage: overmind isolate <project_path> <mission_id>"
    return 1
  fi

  # Resolve to absolute path before sending to daemon (daemon CWD may differ)
  if [ -d "$project_path" ]; then
    project_path="$(cd "$project_path" && pwd)"
  fi

  ep=$(escape_json "$project_path")
  em=$(escape_json "$mission_id")
  json="{\"cmd\":\"isolate\",\"args\":{\"mission_id\":\"$em\",\"project_path\":\"$ep\"}}"
  response=$(send_cmd "$json") || return 1

  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  # Response: {"ok":{"worktree_path":"...","env":{"DB_PORT":"3100",...}}}
  wt=$(printf '%s' "$response" | sed 's/.*"worktree_path":"\([^"]*\)".*/\1/')
  echo "Worktree: $wt"
}

cmd_isolate_teardown() {
  mission_id="${1:-}"
  project_path="${2:-$(pwd)}"

  if [ -z "$mission_id" ]; then
    echo "Missing mission id. Usage: overmind isolate teardown <mission_id> [project_path]"
    return 1
  fi

  if [ -d "$project_path" ]; then
    project_path="$(cd "$project_path" && pwd)"
  fi

  em=$(escape_json "$mission_id")
  ep=$(escape_json "$project_path")
  json="{\"cmd\":\"isolate_teardown\",\"args\":{\"mission_id\":\"$em\",\"project_path\":\"$ep\"}}"
  response=$(send_cmd "$json") || return 1
  extract_ok "$response" > /dev/null || return 1
  echo "Isolation teardown complete for mission $mission_id"
}

usage() {
  cat <<'EOF'
Overmind v0.2.0 — Kubernetes for AI Agents

Usage: overmind <command> [options]

Commands:
  start                    Start the daemon
  shutdown                 Stop the daemon
  run <command>            Spawn a raw command (task mode)
  run --type session       Spawn a session agent
  run --provider claude    Spawn with Claude provider
  run --cwd <path>         Set working directory
  run --name <name>        Set agent name (auto-generated if omitted)
  run --parent <id>        Set parent mission (for hierarchy)
  run --restart <policy>   Restart policy: never, on-failure, always
  run --max-restarts <n>   Max restart attempts within window (0 = unlimited, default 5)
  run --max-seconds <s>    Sliding window for restart budget (default 60)
  run --backoff <ms>       Base backoff in ms (default 1000, exponential)
  run --activity-timeout <s>  Kill after N seconds of no output (0 = disabled)
  claude run <prompt>      Spawn a Claude agent (task mode)
  wait <id>                Wait for mission to finish (returns exit code)
  wait <id> --timeout <ms> Wait with timeout
  send <id> <message>      Send a message to a session
  attach <id>              Attach to a session (TUI)
  detach <id>              Unpause after manual attach
  ps                       List all missions
  ps --tree                Show mission hierarchy as tree
  ps --children <id>       Show children of a mission
  info <id>                Show mission info (os_pid, status, etc.)
  logs <id>                Show mission logs
  result <id>              Show final result of a completed mission (JSON)
  stop <id>                Stop a mission (SIGTERM)
  kill <id>                Kill a mission (SIGKILL)
  kill <id> --cascade      Kill mission and all descendants
  apply <file.toml>        Spawn all agents declared in a blueprint (respects depends_on)
  agents <file.toml>       List agents defined in a blueprint file
  isolate <path> <id>      Set up full isolation (worktree + ports + docker)
  tui                      Launch Nexus — k9s-inspired TUI (q to quit)
  status                   Show daemon health and mission summary
  top                      Live-refresh resource usage per mission (Ctrl+C to exit)
  monitor                  Live-refresh status + mission list (Ctrl+C to exit)
EOF
}
