#!/bin/sh
# Overmind CLI status commands — daemon health and live monitoring.
# Sourced by bin/overmind. Depends on helpers.sh for send_cmd/extract_ok.

# Convert seconds to human-readable uptime (e.g. "2d 3h 14m", "45s")
format_uptime() {
  secs="$1"
  days=$((secs / 86400))
  hours=$(( (secs % 86400) / 3600 ))
  mins=$(( (secs % 3600) / 60 ))

  result=""
  if [ "$days" -gt 0 ]; then
    result="${days}d ${hours}h ${mins}m"
  elif [ "$hours" -gt 0 ]; then
    result="${hours}h ${mins}m"
  elif [ "$mins" -gt 0 ]; then
    result="${mins}m"
  else
    result="${secs}s"
  fi
  printf '%s' "$result"
}

cmd_status() {
  response=$(send_cmd '{"cmd":"status"}') || return 1

  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  # Parse fields from {"ok":{"pid":"...","node":"...","uptime":N,...}}
  pid=$(printf '%s' "$response" | sed 's/.*"pid":"\([^"]*\)".*/\1/')
  node_name=$(printf '%s' "$response" | sed 's/.*"node":"\([^"]*\)".*/\1/')
  uptime=$(printf '%s' "$response" | sed 's/.*"uptime":\([0-9]*\).*/\1/')
  memory=$(printf '%s' "$response" | sed 's/.*"memory_mb":\([0-9]*\).*/\1/')
  procs=$(printf '%s' "$response" | sed 's/.*"process_count":\([0-9]*\).*/\1/')
  ets=$(printf '%s' "$response" | sed 's/.*"ets_table_count":\([0-9]*\).*/\1/')

  # Mission counts from nested "missions":{...}
  running=$(printf '%s' "$response" | sed 's/.*"running":\([0-9]*\).*/\1/')
  stopped=$(printf '%s' "$response" | sed 's/.*"stopped":\([0-9]*\).*/\1/')
  crashed=$(printf '%s' "$response" | sed 's/.*"crashed":\([0-9]*\).*/\1/')
  total=$(printf '%s' "$response" | sed 's/.*"total":\([0-9]*\).*/\1/')

  uptime_str=$(format_uptime "$uptime")

  printf 'Overmind Daemon\n'
  printf '  PID:        %s\n' "$pid"
  printf '  Node:       %s\n' "$node_name"
  printf '  Uptime:     %s\n' "$uptime_str"
  printf '  Memory:     %s MB\n' "$memory"
  printf '  Processes:  %s\n' "$procs"
  printf '  ETS Tables: %s\n' "$ets"
  printf '\n'
  printf 'Missions\n'
  printf '  Running:  %s\n' "$running"
  printf '  Stopped:  %s\n' "$stopped"
  printf '  Crashed:  %s\n' "$crashed"
  printf '  Total:    %s\n' "$total"
}

cmd_monitor() {
  trap 'exit 0' INT
  while true; do
    clear
    cmd_status
    printf '\n'
    cmd_ps
    sleep 2
  done
}
