#!/bin/sh
set -e

CLI="./bin/overmind"

# Clean up any stale daemon
$CLI shutdown 2>/dev/null || true
sleep 0.5
rm -f "$HOME/.overmind/overmind.sock" "$HOME/.overmind/daemon.pid"

$CLI start
sleep 1

out=$($CLI run "echo hello")
echo "$out" | grep -q "Started mission" || { echo "FAIL: run"; $CLI shutdown; exit 1; }
sleep 1

$CLI ps | grep -q "hello" || { echo "FAIL: ps"; $CLI shutdown; exit 1; }

$CLI shutdown
echo "Smoke test passed"
