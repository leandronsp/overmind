#!/bin/sh
# Overmind CLI daemon lifecycle — start and shutdown.
# Sourced by bin/overmind. Depends on helpers.sh for send_cmd.

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
  send_cmd '{"cmd":"shutdown"}' > /dev/null 2>&1 || return 0
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
