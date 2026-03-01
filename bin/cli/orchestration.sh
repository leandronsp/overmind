#!/bin/sh
# Overmind CLI orchestration commands — wait, tree view, cascade kill.
# Sourced by bin/overmind. Depends on helpers.sh for send_cmd/extract_ok.

cmd_wait() {
  id=""
  timeout=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) timeout="$2"; shift 2 ;;
      *)         id="$1"; shift ;;
    esac
  done

  if [ -z "$id" ]; then
    echo "Missing id. Usage: overmind wait <id> [--timeout <ms>]"
    return 1
  fi

  escaped=$(escape_json "$id")
  extra=""
  extra="$extra$(maybe_json_int "timeout" "$timeout")"

  json="{\"cmd\":\"wait\",\"args\":{\"id\":\"$escaped\"$extra}}"
  response=$(send_cmd "$json") || return 1

  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  # Parse status and exit_code from {"ok":{"status":"...","exit_code":N}}
  status=$(printf '%s' "$response" | sed 's/.*"status":"\([^"]*\)".*/\1/')
  exit_code=$(printf '%s' "$response" | sed 's/.*"exit_code":\([0-9]*\).*/\1/')

  echo "Mission $id finished: $status (exit code $exit_code)"
  return "$exit_code"
}
