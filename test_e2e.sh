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
rm -f "$HOME/.overmind/overmind.sock" "$HOME/.overmind/daemon.pid"
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

echo -e "\n${YELLOW}=== Restart: on-failure with max-restarts ===${NC}"
out=$($CLI run --restart on-failure --max-restarts 2 --backoff 200 "false")
id=$(extract_id "$out")
assert_contains "started" "$out" "Started mission"
sleep 3
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "crashed after max restarts" "$status" "crashed"
restarts=$($CLI ps | grep "$id" | awk '{print $5}' || true)
assert_eq "restart count" "$restarts" "2"
logs=$($CLI logs "$id" || true)
assert_contains "restart marker" "$logs" "restart #1"
assert_contains "restart marker 2" "$logs" "restart #2"

echo -e "\n${YELLOW}=== Restart: on-failure does not restart exit 0 ===${NC}"
out=$($CLI run --restart on-failure --max-restarts 3 --backoff 200 "true")
id=$(extract_id "$out")
assert_contains "started" "$out" "Started mission"
sleep 1
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "stopped normally" "$status" "stopped"
restarts=$($CLI ps | grep "$id" | awk '{print $5}' || true)
assert_eq "no restarts" "$restarts" "0"

echo -e "\n${YELLOW}=== Restart: stop during restart cancels restart ===${NC}"
out=$($CLI run --restart on-failure --max-restarts 5 --backoff 5000 "false")
id=$(extract_id "$out")
sleep 1
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "restarting" "$status" "restarting"
$CLI stop "$id" >/dev/null
sleep 1
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "stopped after cancel" "$status" "stopped"

echo -e "\n${YELLOW}=== Stall: activity-timeout kills idle process ===${NC}"
out=$($CLI run --activity-timeout 2 "sleep 60")
id=$(extract_id "$out")
assert_contains "started" "$out" "Started mission"
sleep 4
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "crashed from stall" "$status" "crashed"
logs=$($CLI logs "$id" || true)
assert_contains "stall marker" "$logs" "killed: no activity for"

echo -e "\n${YELLOW}=== Info: full mission details ===${NC}"
out=$($CLI run --name info-agent --cwd /tmp --restart on-failure --max-restarts 3 --activity-timeout 30 "sleep 60")
id=$(extract_id "$out")
sleep 1
info=$($CLI info "$id" || true)
assert_contains "info has os_pid" "$info" "os_pid"
assert_contains "info has status" "$info" "running"
assert_contains "info has name" "$info" "info-agent"
assert_contains "info has cwd" "$info" "/tmp"
assert_contains "info has restart_policy" "$info" "on_failure"
assert_contains "info has restart_count" "$info" "restart_count"
assert_contains "info has type" "$info" "task"
# info by name
info2=$($CLI info "info-agent" || true)
assert_contains "info by name" "$info2" "os_pid"
$CLI stop "$id" >/dev/null
sleep 1

extract_os_pid() {
  printf '%s' "$1" | sed 's/.*"os_pid":\([0-9]*\).*/\1/'
}

echo -e "\n${YELLOW}=== External kill: no self-healing stays crashed ===${NC}"
out=$($CLI run "sleep 60")
id=$(extract_id "$out")
sleep 1
info=$($CLI info "$id")
pid=$(extract_os_pid "$info")
if [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null; then
  echo -e "  ${GREEN}✓${NC} got OS pid $pid from info"
  ((pass++))
else
  echo -e "  ${RED}✗${NC} could not get OS pid from info"
  ((fail++))
fi
kill -9 "$pid" 2>/dev/null
sleep 1
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "crashed after external kill" "$status" "crashed"
restarts=$($CLI ps | grep "$id" | awk '{print $5}' || true)
assert_eq "no restarts (no policy)" "$restarts" "0"

echo -e "\n${YELLOW}=== External kill: self-healing restarts ===${NC}"
out=$($CLI run --restart on-failure --max-restarts 2 --backoff 500 "sleep 60")
id=$(extract_id "$out")
sleep 1
info=$($CLI info "$id")
pid=$(extract_os_pid "$info")
if [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null; then
  echo -e "  ${GREEN}✓${NC} got OS pid $pid from info"
  ((pass++))
else
  echo -e "  ${RED}✗${NC} could not get OS pid from info"
  ((fail++))
fi
kill -9 "$pid" 2>/dev/null
sleep 2
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "restarted after external kill" "$status" "running"
restarts=$($CLI ps | grep "$id" | awk '{print $5}' || true)
assert_eq "restart count is 1" "$restarts" "1"
info2=$($CLI info "$id")
pid2=$(extract_os_pid "$info2")
if [ -n "$pid2" ] && [ "$pid2" != "$pid" ]; then
  echo -e "  ${GREEN}✓${NC} new OS pid $pid2 (was $pid)"
  ((pass++))
else
  echo -e "  ${RED}✗${NC} expected new pid, got '$pid2' (old was $pid)"
  ((fail++))
fi
$CLI stop "$id" >/dev/null
sleep 1

echo -e "\n${YELLOW}=== Sliding window: slow stalls restart beyond max ===${NC}"
# max_restarts=1 within 1s window, but each stall takes 2s → never 2 restarts in 1s
out=$($CLI run --restart on-failure --max-restarts 1 --max-seconds 1 --backoff 50 --activity-timeout 2 "sleep 60")
id=$(extract_id "$out")
assert_contains "started" "$out" "Started mission"
# After 2s: stall kill → restart (window clear) → 2s: stall kill → restart...
# Wait long enough for 2 full stall cycles (each ~2s stall + restart)
sleep 7
restarts=$($CLI ps | grep "$id" | awk '{print $5}' || true)
if [ "$restarts" -ge 2 ] 2>/dev/null; then
  echo -e "  ${GREEN}✓${NC} restarted $restarts times (exceeds max_restarts=1 via sliding window)"
  ((pass++))
else
  echo -e "  ${RED}✗${NC} expected >=2 restarts, got '$restarts'"
  ((fail++))
fi
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "still running or restarting" "$status" "running"
$CLI stop "$id" >/dev/null
sleep 1

echo -e "\n${YELLOW}=== Sliding window: fast crash loop trips circuit breaker ===${NC}"
# max_restarts=2 within 60s window, command exits instantly → 2 restarts in <1s → stops
out=$($CLI run --restart on-failure --max-restarts 2 --max-seconds 60 --backoff 50 "false")
id=$(extract_id "$out")
assert_contains "started" "$out" "Started mission"
sleep 3
status=$($CLI ps | grep "$id" | awk '{print $4}' || true)
assert_eq "crashed from crash loop" "$status" "crashed"
restarts=$($CLI ps | grep "$id" | awk '{print $5}' || true)
assert_eq "exactly 2 restarts" "$restarts" "2"

echo -e "\n${YELLOW}=== Wait: blocks until finish ===${NC}"
out=$($CLI run "sh -c 'sleep 1; exit 0'")
id=$(extract_id "$out")
assert_contains "started" "$out" "Started mission"
wait_out=$($CLI wait "$id")
assert_contains "wait result" "$wait_out" "finished"
assert_contains "wait exit code" "$wait_out" "exit code 0"
assert_contains "wait status" "$wait_out" "stopped"

echo -e "\n${YELLOW}=== Wait: already-exited mission ===${NC}"
out=$($CLI run "true")
id=$(extract_id "$out")
sleep 1
wait_out=$($CLI wait "$id")
assert_contains "immediate wait" "$wait_out" "finished"
assert_contains "exit code 0" "$wait_out" "exit code 0"

echo -e "\n${YELLOW}=== Wait: timeout ===${NC}"
out=$($CLI run "sleep 60")
id=$(extract_id "$out")
sleep 0.5
wait_out=$($CLI wait "$id" --timeout 500 2>&1 || true)
assert_contains "timeout error" "$wait_out" "timeout"
$CLI kill "$id" >/dev/null

echo -e "\n${YELLOW}=== Wait: non-zero exit code ===${NC}"
out=$($CLI run "sh -c 'exit 42'")
id=$(extract_id "$out")
wait_exit=0
$CLI wait "$id" || wait_exit=$?
assert_eq "exit code propagated" "$wait_exit" "42"

echo -e "\n${YELLOW}=== Parent: run with --parent ===${NC}"
out=$($CLI run --name "e2e-parent" "sleep 60")
parent_id=$(extract_id "$out")
assert_contains "parent started" "$out" "Started mission"
out=$($CLI run --parent "$parent_id" "sleep 60")
child_id=$(extract_id "$out")
assert_contains "child started" "$out" "Started mission"
sleep 1

echo -e "\n${YELLOW}=== Parent: ps --tree shows hierarchy ===${NC}"
tree_out=$($CLI ps --tree)
assert_contains "tree shows parent" "$tree_out" "$parent_id"
assert_contains "tree shows child" "$tree_out" "$child_id"

echo -e "\n${YELLOW}=== Parent: ps --children ===${NC}"
children_out=$($CLI ps --children "$parent_id")
assert_contains "children shows child" "$children_out" "$child_id"

echo -e "\n${YELLOW}=== Parent: --parent by name ===${NC}"
out=$($CLI run --parent "e2e-parent" "sleep 60")
child2_id=$(extract_id "$out")
assert_contains "child by name started" "$out" "Started mission"
children_out=$($CLI ps --children "$parent_id")
assert_contains "children has child2" "$children_out" "$child2_id"

echo -e "\n${YELLOW}=== Parent: invalid parent ===${NC}"
out=$($CLI run --parent "nonexist" "sleep 60" 2>&1 || true)
assert_contains "parent not found" "$out" "parent_not_found"

echo -e "\n${YELLOW}=== Kill cascade: removes parent and children ===${NC}"
$CLI kill "$parent_id" --cascade >/dev/null
sleep 1
found_parent=$($CLI ps | grep "$parent_id" || true)
assert_eq "parent removed" "$found_parent" ""
found_child=$($CLI ps | grep "$child_id" || true)
assert_eq "child removed" "$found_child" ""
found_child2=$($CLI ps | grep "$child2_id" || true)
assert_eq "child2 removed" "$found_child2" ""

echo -e "\n${YELLOW}=== Kill without cascade: children survive ===${NC}"
out=$($CLI run "sleep 60")
p_id=$(extract_id "$out")
out=$($CLI run --parent "$p_id" "sleep 60")
c_id=$(extract_id "$out")
sleep 0.5
$CLI kill "$p_id" >/dev/null
sleep 0.5
# grep by ^id to avoid matching parent column in child rows
found_parent=$($CLI ps | awk '{print $1}' | grep "$p_id" || true)
assert_eq "parent removed" "$found_parent" ""
c_status=$($CLI ps | grep "$c_id" | awk '{print $4}' || true)
assert_eq "child still running" "$c_status" "running"
$CLI kill "$c_id" >/dev/null

echo -e "\n${YELLOW}=== Cleanup ===${NC}"
$CLI shutdown

echo -e "\n${YELLOW}==============================${NC}"
echo -e "  ${GREEN}$pass passed${NC}, ${RED}$fail failed${NC}"
echo -e "${YELLOW}==============================${NC}"

[ "$fail" -eq 0 ] && exit 0 || exit 1
