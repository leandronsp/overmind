#!/bin/sh
# Overmind CLI helpers — sourced by bin/overmind

escape_json() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

send_cmd() {
  if [ ! -S "$SOCK" ]; then
    echo "Daemon not running. Start with: overmind start" >&2
    return 1
  fi
  response=$(printf '%s\n' "$1" | nc -U "$SOCK" 2>/dev/null) || {
    echo "Daemon not running. Start with: overmind start" >&2
    return 1
  }
  printf '%s' "$response"
}

extract_ok() {
  response="$1"
  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi
  printf '%s' "$response" | sed 's/.*"ok":\(.*\)}/\1/' | sed 's/^"//; s/"$//'
}

unescape_json() {
  printf '%b' "$1"
}

maybe_json_str() {
  key="$1"
  val="$2"
  if [ -n "$val" ]; then
    printf ',"%s":"%s"' "$key" "$(escape_json "$val")"
  fi
}

maybe_json_int() {
  key="$1"
  val="$2"
  if [ -n "$val" ]; then
    printf ',"%s":%s' "$key" "$val"
  fi
}

# Send a simple id-based command and print a confirmation message
simple_id_cmd() {
  cmd_name="$1"; id="$2"; verb="$3"
  escaped=$(escape_json "$id")
  response=$(send_cmd "{\"cmd\":\"$cmd_name\",\"args\":{\"id\":\"$escaped\"}}") || return 1
  extract_ok "$response" > /dev/null || return 1
  echo "$verb mission $id"
}
