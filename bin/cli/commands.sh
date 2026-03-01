#!/bin/sh
# Overmind CLI commands — user-facing cmd_* functions dispatched by bin/overmind.
# Each function builds JSON, sends it over the Unix socket, and formats output.

# --- Daemon lifecycle ---

cmd_start() {
  # If socket exists, check if daemon is actually alive (stale socket from crash)
  if [ -S "$SOCK" ]; then
    if printf '{"cmd":"ping"}\n' | nc -U "$SOCK" >/dev/null 2>&1; then
      echo "Daemon is already running"
      return 0
    fi
    rm -f "$SOCK" "$PIDFILE"
  fi

  mkdir -p "$(dirname "$SOCK")"
  nohup "$DAEMON" __daemon__ > "$LOGFILE" 2>&1 &
  daemon_pid=$!
  echo "$daemon_pid" > "$PIDFILE"

  # Poll for socket: 20 × 0.25s = 5s max wait for daemon to create the socket
  i=0
  while [ $i -lt 20 ]; do
    if [ -S "$SOCK" ]; then
      echo "Daemon started (PID $daemon_pid)"
      return 0
    fi
    sleep 0.25
    i=$((i + 1))
  done
  echo "Daemon process started but not yet reachable"
}

cmd_shutdown() {
  # Daemon removes socket asynchronously after receiving shutdown command
  response=$(send_cmd '{"cmd":"shutdown"}') || return 0
  # Poll for socket removal: 20 × 0.1s = 2s max wait
  i=0
  while [ $i -lt 20 ]; do
    [ ! -S "$SOCK" ] && break
    sleep 0.1
    i=$((i + 1))
  done
  rm -f "$PIDFILE"
  echo "Daemon stopped"
}

cmd_run() {
  command=""
  type="task"
  provider="raw"
  cwd=""
  name=""
  restart=""
  max_restarts=""
  max_seconds=""
  backoff=""
  activity_timeout=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --type)             type="$2"; shift 2 ;;
      --provider)         provider="$2"; shift 2 ;;
      --cwd)              cwd="$2"; shift 2 ;;
      --name)             name="$2"; shift 2 ;;
      --restart)          restart="$2"; shift 2 ;;
      --max-restarts)     max_restarts="$2"; shift 2 ;;
      --max-seconds)      max_seconds="$2"; shift 2 ;;
      --backoff)          backoff="$2"; shift 2 ;;
      --activity-timeout) activity_timeout="$2"; shift 2 ;;
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
  extra="$extra$(maybe_json_str "restart" "$restart")"
  extra="$extra$(maybe_json_int "max_restarts" "$max_restarts")"
  extra="$extra$(maybe_json_int "max_seconds" "$max_seconds")"
  extra="$extra$(maybe_json_int "backoff" "$backoff")"
  extra="$extra$(maybe_json_int "activity_timeout" "$activity_timeout")"

  json="{\"cmd\":\"run\",\"args\":{\"command\":\"$escaped\",\"type\":\"$type\",\"provider\":\"$provider\"$extra}}"
  response=$(send_cmd "$json") || return 1
  id=$(extract_ok "$response") || return 1
  echo "Started mission $id"
}

cmd_claude_run() {
  if [ $# -eq 0 ]; then
    echo "Missing prompt. Usage: overmind claude run <prompt>"
    return 1
  fi
  cmd_run --provider claude "$@"
}

cmd_ps() {
  response=$(send_cmd '{"cmd":"ps"}') || return 1
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
  printf '%s\n' "$response" | sed 's/.*"ok"://' | sed 's/}$//'
}

cmd_logs() {
  escaped=$(escape_json "$1")
  response=$(send_cmd "{\"cmd\":\"logs\",\"args\":{\"id\":\"$escaped\"}}") || return 1
  text=$(extract_ok "$response") || return 1
  unescape_json "$text"
}

cmd_stop() { simple_id_cmd "stop" "$1" "Stopped"; }
cmd_kill() { simple_id_cmd "kill" "$1" "Killed"; }

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

  # Response: {"ok":{"session_id":"...","cwd":"..."}}
  session_id=$(printf '%s' "$response" | sed 's/.*"session_id":"\([^"]*\)".*/\1/')
  cwd=$(printf '%s' "$response" | sed 's/.*"cwd":"\([^"]*\)".*/\1/')

  # No session yet (first prompt hasn't been sent) — unpause and bail
  if [ "$session_id" = "null" ] || [ -z "$session_id" ]; then
    printf '{\"cmd\":\"unpause\",\"args\":{\"id\":\"%s\"}}\n' "$escaped" | nc -U "$SOCK" > /dev/null 2>&1
    echo "Mission $id has no session ID yet"
    return 1
  fi

  # Unpause on ALL exit paths: Ctrl+C, Claude crash, normal exit
  trap "printf '{\"cmd\":\"unpause\",\"args\":{\"id\":\"$escaped\"}}\\n' | nc -U \"$SOCK\" > /dev/null 2>&1" EXIT

  # Claude session must run in the mission's CWD for --resume to find its state
  if [ -n "$cwd" ] && [ "$cwd" != "null" ]; then
    cd "$cwd" || true
  fi

  claude --resume "$session_id"
}

usage() {
  cat <<'EOF'
Overmind v0.1.0 — Kubernetes for AI Agents

Usage: overmind <command> [options]

Commands:
  start                    Start the daemon
  shutdown                 Stop the daemon
  run <command>            Spawn a raw command (task mode)
  run --type session       Spawn a session agent
  run --provider claude    Spawn with Claude provider
  run --cwd <path>         Set working directory
  run --name <name>        Set agent name (auto-generated if omitted)
  run --restart <policy>   Restart policy: never, on-failure, always
  run --max-restarts <n>   Max restart attempts within window (0 = unlimited, default 5)
  run --max-seconds <s>    Sliding window for restart budget (default 60)
  run --backoff <ms>       Base backoff in ms (default 1000, exponential)
  run --activity-timeout <s>  Kill after N seconds of no output (0 = disabled)
  claude run <prompt>      Spawn a Claude agent (task mode)
  send <id> <message>      Send a message to a session
  attach <id>              Attach to a session (TUI)
  detach <id>              Unpause after manual attach
  ps                       List all missions
  info <id>                Show mission info (os_pid, status, etc.)
  logs <id>                Show mission logs
  stop <id>                Stop a mission (SIGTERM)
  kill <id>                Kill a mission (SIGKILL)
EOF
}
