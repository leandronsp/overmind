#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLI="./bin/overmind"

pass=0
fail=0

assert_contains() {
  local label="$1" actual="$2" expected="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo -e "  ${GREEN}✓${NC} $label"
    ((pass++))
  else
    echo -e "  ${RED}✗${NC} $label — expected '$expected' in: $actual"
    ((fail++))
  fi
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo -e "  ${GREEN}✓${NC} $label"
    ((pass++))
  else
    echo -e "  ${RED}✗${NC} $label — expected '$expected', got '$actual'"
    ((fail++))
  fi
}

extract_id() {
  echo "$1" | awk '{print $NF}'
}

echo -e "${YELLOW}=== Building ===${NC}"
mix build 2>&1 | tail -1

echo -e "\n${YELLOW}=== Daemon ===${NC}"
$CLI shutdown 2>/dev/null || true
sleep 0.5
$CLI start
sleep 1

echo -e "\n${YELLOW}=== Raw: simple echo ===${NC}"
out=$($CLI run "echo hello")
id=$(extract_id "$out")
assert_contains "started" "$out" "Started mission"
sleep 1
logs=$($CLI logs "$id" || true)
assert_contains "logs" "$logs" "hello"
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "stopped" "$status" "stopped"

echo -e "\n${YELLOW}=== Names: run with --name ===${NC}"
out=$($CLI run --name my-agent "echo named")
id=$(extract_id "$out")
assert_contains "started with name" "$out" "Started mission"
sleep 1
ps_out=$($CLI ps)
assert_contains "ps shows name" "$ps_out" "my-agent"
logs=$($CLI logs "my-agent" || true)
assert_contains "logs by name" "$logs" "named"

echo -e "\n${YELLOW}=== Names: stop by name ===${NC}"
out=$($CLI run --name stopper "sleep 60")
sleep 1
$CLI stop "stopper" >/dev/null
sleep 1
status=$($CLI ps | grep "stopper" | awk '{print $4}' || true)
assert_eq "stopped by name" "$status" "stopped"

echo -e "\n${YELLOW}=== Raw: cwd ===${NC}"
out=$($CLI run --cwd /tmp "pwd")
id=$(extract_id "$out")
assert_contains "started with cwd" "$out" "Started mission"
sleep 1
logs=$($CLI logs "$id" || true)
assert_contains "cwd logs show tmp" "$logs" "tmp"

echo -e "\n${YELLOW}=== Raw: semicolon chain ===${NC}"
out=$($CLI run "echo oi; sleep 2; echo tchau")
id=$(extract_id "$out")
sleep 1
logs=$($CLI logs "$id" || true)
assert_contains "first output" "$logs" "oi"
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "still running" "$status" "running"
sleep 3
logs=$($CLI logs "$id" || true)
assert_contains "chain completed" "$logs" "tchau"
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "stopped after chain" "$status" "stopped"

echo -e "\n${YELLOW}=== Raw: && chain ===${NC}"
out=$($CLI run "echo first && sleep 1 && echo last")
id=$(extract_id "$out")
sleep 3
logs=$($CLI logs "$id" || true)
assert_contains "first" "$logs" "first"
assert_contains "last" "$logs" "last"

echo -e "\n${YELLOW}=== Raw: && short-circuit ===${NC}"
out=$($CLI run "echo before && false && echo after")
id=$(extract_id "$out")
sleep 1
logs=$($CLI logs "$id" || true)
assert_contains "before runs" "$logs" "before"
if echo "$logs" | grep -q "after"; then
  echo -e "  ${RED}✗${NC} after should not appear"
  ((fail++))
else
  echo -e "  ${GREEN}✓${NC} after skipped"
  ((pass++))
fi
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "crashed on false" "$status" "crashed"

echo -e "\n${YELLOW}=== Session: spawn, send, logs ===${NC}"
out=$($CLI run --type session)
id=$(extract_id "$out")
assert_contains "session started" "$out" "Started mission"
sleep 0.5
$CLI send "$id" "hello session" >/dev/null
sleep 0.5
logs=$($CLI logs "$id" || true)
assert_contains "session log has human" "$logs" "\[human\] hello session"
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "session running" "$status" "running"
$CLI stop "$id" >/dev/null
sleep 0.5

echo -e "\n${YELLOW}=== Claude: run ===${NC}"
out=$($CLI claude run "write a haiku about elixir then another about erlang")
id=$(extract_id "$out")
assert_contains "started" "$out" "Started mission"
# poll until logs appear while still running
got_streaming=false
echo -n "  waiting for streaming output"
for i in $(seq 1 60); do
  sleep 0.5
  status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
  logs=$($CLI logs "$id" || true)
  if [ -n "$logs" ] && [ "$status" = "running" ]; then
    got_streaming=true
    break
  fi
  [ "$status" != "running" ] && break
  echo -n "."
done
echo ""
if $got_streaming; then
  echo -e "  ${GREEN}✓${NC} logs while still running"
  ((pass++))
else
  echo -e "  ${RED}✗${NC} no logs while running (status=$status, logs='$(echo "$logs" | head -c 80)')"
  ((fail++))
fi
# wait for finish
echo -n "  waiting for finish"
for i in $(seq 1 20); do
  status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
  [ "$status" != "running" ] && break
  echo -n "."
  sleep 2
done
echo ""
logs=$($CLI logs "$id" || true)
assert_contains "claude produced output" "$logs" "."
if [ "$status" = "stopped" ] || [ "$status" = "crashed" ]; then
  echo -e "  ${GREEN}✓${NC} claude finished ($status)"
  ((pass++))
else
  echo -e "  ${RED}✗${NC} claude finished — expected stopped/crashed, got '$status'"
  ((fail++))
fi

echo -e "\n${YELLOW}=== Stop ===${NC}"
out=$($CLI run "sleep 60")
id=$(extract_id "$out")
sleep 1
$CLI stop "$id" >/dev/null
sleep 1
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "stopped" "$status" "stopped"

echo -e "\n${YELLOW}=== Kill ===${NC}"
out=$($CLI run "sleep 60")
id=$(extract_id "$out")
sleep 1
$CLI kill "$id" >/dev/null
sleep 1
found=$($CLI ps | grep "$id" || true)
assert_eq "removed from ps" "$found" ""

echo -e "\n${YELLOW}=== Cleanup ===${NC}"
$CLI shutdown

echo -e "\n${YELLOW}==============================${NC}"
echo -e "  ${GREEN}$pass passed${NC}, ${RED}$fail failed${NC}"
echo -e "${YELLOW}==============================${NC}"

[ "$fail" -eq 0 ] && exit 0 || exit 1
