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

  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi

  # Response: {"ok":{"id":"...","name":"..."}}
  id=$(printf '%s' "$response" | sed 's/.*"id":"\([^"]*\)".*/\1/')
  name=$(printf '%s' "$response" | sed 's/.*"name":"\([^"]*\)".*/\1/')
  echo "Started pipeline $id ($name)"
}
