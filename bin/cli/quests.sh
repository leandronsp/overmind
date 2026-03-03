#!/bin/sh
# Overmind CLI quest and ritual commands — one-shot jobs and cron-scheduled tasks.
# Sourced by bin/overmind. Depends on helpers.sh for send_cmd/extract_ok.

# --- Quest commands ---

cmd_quest_run() {
  name=""
  command=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *)      command="$command $1"; shift ;;
    esac
  done
  command=$(printf '%s' "$command" | sed 's/^ //')

  if [ -z "$command" ]; then
    echo "Missing command. Usage: overmind quest run [--name <name>] <command>"
    return 1
  fi

  # Default name to command string if not provided
  if [ -z "$name" ]; then
    name="$command"
  fi

  ename=$(escape_json "$name")
  ecmd=$(escape_json "$command")
  json="{\"cmd\":\"quest_run\",\"args\":{\"name\":\"$ename\",\"command\":\"$ecmd\"}}"
  response=$(send_cmd "$json") || return 1

  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  id=$(printf '%s' "$response" | sed 's/.*"id":"\([^"]*\)".*/\1/')
  echo "Quest started: $id ($name)"
}

cmd_quest_list() {
  response=$(send_cmd '{"cmd":"quest_list"}') || return 1
  text=$(extract_ok "$response") || return 1
  unescape_json "$text"
}

# --- Ritual commands ---

cmd_ritual_create() {
  if [ $# -lt 3 ]; then
    echo "Usage: overmind ritual create <name> \"<cron_expr>\" <command>"
    return 1
  fi

  name="$1"
  cron_expr="$2"
  shift 2
  command="$*"

  ename=$(escape_json "$name")
  ecron=$(escape_json "$cron_expr")
  ecmd=$(escape_json "$command")
  json="{\"cmd\":\"ritual_create\",\"args\":{\"name\":\"$ename\",\"cron\":\"$ecron\",\"command\":\"$ecmd\"}}"
  response=$(send_cmd "$json") || return 1

  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  id=$(printf '%s' "$response" | sed 's/.*"id":"\([^"]*\)".*/\1/')
  echo "Ritual created: $id ($name)"
}

cmd_ritual_list() {
  response=$(send_cmd '{"cmd":"ritual_list"}') || return 1
  text=$(extract_ok "$response") || return 1
  unescape_json "$text"
}

cmd_ritual_delete() {
  if [ -z "$1" ]; then
    echo "Usage: overmind ritual delete <name>"
    return 1
  fi

  escaped=$(escape_json "$1")
  response=$(send_cmd "{\"cmd\":\"ritual_delete\",\"args\":{\"name\":\"$escaped\"}}") || return 1
  extract_ok "$response" > /dev/null || return 1
  echo "Ritual deleted: $1"
}
