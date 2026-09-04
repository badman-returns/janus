#!/usr/bin/env bash
# dm-stop.sh — stopping a machine on purpose has to be recorded, or the fleet registry keeps
# claiming a dead machine is running and dm-boot.sh treats the operator's decision as a crash
# to recover from. The entry is marked, never deleted: the fleet page still needs it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/dm-stop.sh"; BOOT="$HERE/../scripts/dm-boot.sh"
J="$HERE/../scripts/janus.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL test_dm_stop: $1"; exit 1; }
PROJ="dmstoptest-$$"
mkdir -p "$T/proj/.delivery/inbox"
cat > "$T/proj/.delivery/config.json" <<JSON
{ "project": "$PROJ", "services": { "web": "sleep 300" } }
JSON
REG="$T/reg.json"
cat > "$REG" <<JSON
{ "$PROJ": { "dir": "$T/proj", "session": "dm-$PROJ", "port": 5501, "ttyd_port": 5601, "started": "2026-09-04 10:00" } }
JSON
r(){ python3 -c "import json,sys;print(json.load(open('$REG'))['$PROJ'].get(sys.argv[1],''))" "$1"; }

cd "$T/proj"
out=$(DM_REGISTRY="$REG" bash "$S") || fail "exit $?"

# 1. the handoff is written first, because everything after it is destructive
[ -s .delivery/HANDOFF.md ] || fail "no handoff written"
printf '%s' "$out" | grep -q "^handoff" || fail "handoff step not reported: $out"
# 2. one line per step, so the operator sees what happened
printf '%s' "$out" | grep -q "^service   " || fail "service step not reported: $out"
printf '%s' "$out" | grep -q "^session   dm-$PROJ" || fail "session step not reported: $out"
printf '%s' "$out" | grep -q "^registry  $PROJ marked stopped" || fail "registry step not reported: $out"
# 3. the registry says stopped, when, and still has everything else
[ "$(r state)" = stopped ] || fail "state not stopped: '$(r state)'"
case "$(r stopped)" in 20*T*Z) : ;; *) fail "stopped not ISO: '$(r stopped)'" ;; esac
[ "$(r dir)" = "$T/proj" ] || fail "entry lost its dir"
[ "$(r port)" = 5501 ] || fail "entry lost its port"
[ "$(r started)" = "2026-09-04 10:00" ] || fail "entry lost its started"
[ "$(python3 -c "import json;print(len(json.load(open('$REG'))))")" = 1 ] || fail "entry deleted"

# 4. --pause says paused instead, and leaves the session alone
out=$(DM_REGISTRY="$REG" bash "$S" --pause) || fail "--pause exit $?"
[ "$(r state)" = paused ] || fail "--pause did not mark paused: '$(r state)'"
printf '%s' "$out" | grep -q "left running (--pause)" || fail "--pause killed or misreported the session: $out"

# 5. a deliberately stopped machine is not a crash: dm-boot.sh leaves it alone and the
#    picker names its state instead of guessing
python3 - "$REG" "$PROJ" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); r[sys.argv[2]]["state"] = "stopped"
json.dump(r, open(sys.argv[1], "w"), indent=2)
PY
out=$(DM_REGISTRY="$REG" bash "$BOOT") || fail "dm-boot exit $?"
[ "$out" = "skipped-stopped $PROJ" ] || fail "dm-boot did not skip a stopped machine: $out"
row=$(DM_REGISTRY="$REG" bash "$J" --list) || fail "janus --list exit $?"
[ "$(printf '%s' "$row" | cut -f8)" = stopped ] || fail "janus --list does not carry state: $row"
[ -n "$(printf '%s' "$row" | cut -f7)" ] || fail "janus --list lost the recap column: $row"
render=$(DM_REGISTRY="$REG" bash "$J" < /dev/null) || fail "janus render exit $?"
printf '%s' "$render" | grep -q "stopped" || fail "picker does not show the state: $render"

# 6. a real session is actually killed (only where tmux exists)
if command -v tmux >/dev/null 2>&1; then
  tmux new-session -d -s "dm-$PROJ" -n control 2>/dev/null || fail "could not create a test session"
  tmux new-window -t "dm-$PROJ" -n web
  out=$(DM_REGISTRY="$REG" bash "$S") || { tmux kill-session -t "dm-$PROJ" 2>/dev/null; fail "exit $? with a live session"; }
  printf '%s' "$out" | grep -q "^service   web stopped" || { tmux kill-session -t "dm-$PROJ" 2>/dev/null; fail "live service window not stopped: $out"; }
  printf '%s' "$out" | grep -q "^session   dm-$PROJ killed" || { tmux kill-session -t "dm-$PROJ" 2>/dev/null; fail "session not killed: $out"; }
  tmux has-session -t "dm-$PROJ" 2>/dev/null && { tmux kill-session -t "dm-$PROJ"; fail "session survived dm-stop.sh"; }
fi

# 7. outside a Janus project it refuses rather than half-running
cd "$T"; DM_REGISTRY="$REG" bash "$S" >/dev/null 2>&1; [ $? -eq 1 ] || fail "should exit 1 with no config.json"

echo "PASS test_dm_stop"
