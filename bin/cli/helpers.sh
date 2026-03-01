#!/bin/sh
# Overmind CLI helpers — JSON encoding, socket transport, response parsing.
# Sourced by bin/overmind. All functions here are used by commands.sh.

# --- JSON encoding ---

escape_json() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

unescape_json() {
  printf '%b' "$1"
}

# --- Socket transport ---

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

# --- Response parsing ---

# Parse {"ok":...} or {"error":"..."} responses from the daemon.
# First sed strips the outer {"ok":...} wrapper, second strips surrounding quotes
# so callers get the raw value (e.g. an id string or escaped text).
extract_ok() {
  response="$1"
  if printf '%s' "$response" | grep -q '"error"'; then
    err=$(printf '%s' "$response" | sed 's/.*"error":"\([^"]*\)".*/\1/')
    echo "Error: $err" >&2
    return 1
  fi
  printf '%s' "$response" | sed 's/.*"ok":\(.*\)}/\1/' | sed 's/^"//; s/"$//'
}

# --- Optional JSON field builders ---

# Append a JSON key-value pair only when val is non-empty.
# Uses if/then instead of [ -n ] && printf because set -e treats
# the short-circuit false exit as a script failure.
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

# --- Command helpers ---

# Shared pattern for stop/kill/detach — commands that take only an id,
# send it to the daemon, and print a verb + mission id on success.
simple_id_cmd() {
  cmd_name="$1"; id="$2"; verb="$3"
  escaped=$(escape_json "$id")
  response=$(send_cmd "{\"cmd\":\"$cmd_name\",\"args\":{\"id\":\"$escaped\"}}") || return 1
  extract_ok "$response" > /dev/null || return 1
  echo "$verb mission $id"
}
