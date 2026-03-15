#!/bin/sh
# Overmind CLI blueprint commands — apply and agents.
# Sourced by bin/overmind. Depends on helpers.sh for send_cmd/escape_json.

cmd_agents() {
  if [ -z "${1:-}" ]; then
    echo "Missing path. Usage: overmind agents <blueprint.toml>"
    return 1
  fi

  path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  escaped=$(escape_json "$path")
  response=$(send_cmd "{\"cmd\":\"agents\",\"args\":{\"path\":\"$escaped\"}}") || return 1

  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  # Response: {"ok":[{"name":"...","command":"...","depends_on":[...]},...]}
  # Parse each agent entry and print name + deps
  printf '%s' "$response" | sed 's/.*"ok":\[//; s/\]}//' | tr '}' '\n' | while IFS= read -r entry; do
    name=$(printf '%s' "$entry" | sed 's/.*"name":"\([^"]*\)".*/\1/')
    deps=$(printf '%s' "$entry" | sed 's/.*"depends_on":\[\([^]]*\)\].*/\1/' | tr -d '"')
    if [ -n "$name" ] && [ "$name" != "$entry" ]; then
      if [ -n "$deps" ] && [ "$deps" != "$entry" ]; then
        echo "$name (depends on: $deps)"
      else
        echo "$name"
      fi
    fi
  done
}

cmd_apply() {
  if [ -z "${1:-}" ]; then
    echo "Missing path. Usage: overmind apply <blueprint.toml>"
    return 1
  fi

  path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  escaped=$(escape_json "$path")
  response=$(send_cmd "{\"cmd\":\"apply\",\"args\":{\"path\":\"$escaped\"}}") || return 1

  # Check for structured error (pipeline failure)
  if printf '%s' "$response" | grep -q '"error"'; then
    if printf '%s' "$response" | grep -q '"reason"'; then
      agent=$(printf '%s' "$response" | sed 's/.*"agent":"\([^"]*\)".*/\1/')
      reason=$(printf '%s' "$response" | sed 's/.*"reason":"\([^"]*\)".*/\1/')
      echo "Pipeline failed at agent '$agent': $reason" >&2

      # Print completed agents
      if printf '%s' "$response" | grep -q '"completed":\[{'; then
        echo "Completed:" >&2
        printf '%s' "$response" | sed 's/.*"completed":\[//; s/\]}.*//' | tr '}' '\n' | while IFS= read -r entry; do
          cname=$(printf '%s' "$entry" | sed 's/.*"name":"\([^"]*\)".*/\1/')
          cstatus=$(printf '%s' "$entry" | sed 's/.*"status":"\([^"]*\)".*/\1/')
          if [ -n "$cname" ] && [ "$cname" != "$entry" ]; then
            echo "  $cname: $cstatus" >&2
          fi
        done
      fi
      return 1
    else
      err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
      echo "Error: $err" >&2
      return 1
    fi
  fi

  # Success: {"ok":[{"name":"...","id":"...","status":"...","exit_code":N},...]}
  printf '%s' "$response" | sed 's/.*"ok":\[//; s/\]}//' | tr '}' '\n' | while IFS= read -r entry; do
    name=$(printf '%s' "$entry" | sed 's/.*"name":"\([^"]*\)".*/\1/')
    status=$(printf '%s' "$entry" | sed 's/.*"status":"\([^"]*\)".*/\1/')
    exit_code=$(printf '%s' "$entry" | sed 's/.*"exit_code":\([0-9]*\).*/\1/')
    if [ -n "$name" ] && [ "$name" != "$entry" ]; then
      echo "$name: $status (exit code ${exit_code:-?})"
    fi
  done
}
