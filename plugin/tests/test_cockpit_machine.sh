#!/usr/bin/env bash
# POST /api/machine {action:"stop"|"pause"} — the stop button.
#
# The hard part is not running dm-stop.sh, it is answering the browser first: stop kills the
# tmux session the mission-control server itself runs in, so an implementation that shells out
# synchronously dies mid-response and the operator sees a network error instead of a
# confirmation. So this test asserts BOTH halves against a real, uniquely-named throwaway tmux
# session (never a dm-* machine anyone is using): the HTTP response arrives, and the machine
# then actually goes down.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRV="$HERE/../../plugin-mc/mission-control/server.js"; SCRIPTS="$HERE/../scripts"
T=$(mktemp -d); PORT=5595; PID=""
PROJ="cockpitmachinetest-$$"; SESSION="dm-$PROJ"
cleanup(){ [ -n "$PID" ] && kill "$PID" 2>/dev/null; tmux kill-session -t "$SESSION" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
fail(){ echo "FAIL test_cockpit_machine: $1"; exit 1; }
P="$T/proj"

mkdir -p "$P/.delivery/inbox" "$T/.delivery-machine"
cat > "$P/.delivery/config.json" <<JSON
{ "project": "$PROJ", "services": { "web": "sleep 300" } }
JSON
cat > "$T/.delivery-machine/registry.json" <<JSON
{ "$PROJ": { "dir": "$P", "session": "$SESSION", "port": $PORT, "ttyd_port": 5695, "started": "2026-09-04 10:00" } }
JSON
reg(){ python3 -c "
import json,sys
try: r=json.load(open('$T/.delivery-machine/registry.json'))
except Exception: print('unreadable'); raise SystemExit
print(r.get('$PROJ',{}).get(sys.argv[1],''))" "$1"; }

boot(){ HOME="$T" node "$SRV" --port $PORT --project "$P" --session "$SESSION" --scripts "$SCRIPTS" >/dev/null 2>&1 & PID=$!; disown
  for i in $(seq 1 40); do curl -sf "localhost:$PORT/api/state" >/dev/null && break; sleep 0.25; done
  curl -sf "localhost:$PORT/api/state" >/dev/null || fail "server did not come up on $PORT"; }
call(){ curl -s --max-time 8 -X POST -H 'content-type: application/json' -d "$1" "localhost:$PORT/api/machine"; }
# wait for a condition instead of sleeping blind: the script starts a second later, on purpose
until_ok(){ for i in $(seq 1 60); do eval "$2" >/dev/null 2>&1 && return 0; sleep 0.25; done; fail "$1"; }

boot

# 1. a bad action is refused, and refusing it must not take the machine down
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
   -d '{"action":"reboot"}' "localhost:$PORT/api/machine")" = 400 ] || fail "an unknown action was accepted"
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST -d 'not json' "localhost:$PORT/api/machine")" = 400 ] \
  || fail "a non-JSON body was accepted"
curl -sf "localhost:$PORT/api/state" >/dev/null || fail "a refused action killed the server"
[ -e "$P/.delivery/HANDOFF.md" ] && fail "a refused action still ran dm-stop.sh"

# 2. --pause: the response arrives, the handoff is written, the session is KEPT, registry says paused
command -v tmux >/dev/null 2>&1 || { echo "PASS test_cockpit_machine (no tmux — HTTP contract only)"; exit 0; }
tmux new-session -d -s "$SESSION" -n control || fail "could not create the throwaway session"
tmux new-window -t "$SESSION" -n web

out=$(call '{"action":"pause"}') || fail "pause: curl failed (exit $?) — the response did not arrive"
printf '%s' "$out" | python3 -c "
import json,sys; d=json.load(sys.stdin)
assert d.get('ok') is True and d.get('action')=='pause', d" || fail "pause: bad response body: $out"

until_ok "pause never wrote the handoff" '[ -s "'"$P"'/.delivery/HANDOFF.md" ]'
until_ok "pause never marked the registry" '[ "$(python3 -c "
import json;print(json.load(open(\"'"$T"'/.delivery-machine/registry.json\"))[\"'"$PROJ"'\"].get(\"state\",\"\"))")" = paused ]'
tmux has-session -t "$SESSION" 2>/dev/null || fail "pause killed the session — that is what stop is for"
curl -sf "localhost:$PORT/api/state" >/dev/null || fail "pause took the mission-control server down with it"

# 3. stop: same response, and this time the session really dies — with this server inside it.
#    The server is a child of THIS test, not of the tmux session, so it survives where a real
#    one would not; what is being proved here is that the reply is sent before the script runs
#    and that the script is not killed along with the pane it was started from.
rm -f "$P/.delivery/HANDOFF.md"
out=$(call '{"action":"stop"}') || fail "stop: curl failed (exit $?) — the response died with the machine"
printf '%s' "$out" | python3 -c "
import json,sys; d=json.load(sys.stdin)
assert d.get('ok') is True and d.get('action')=='stop', d
assert 'offline' in (d.get('note') or ''), d" || fail "stop: bad response body: $out"

until_ok "stop never wrote the handoff" '[ -s "'"$P"'/.delivery/HANDOFF.md" ]'
until_ok "stop did not kill the session" '! tmux has-session -t "'"$SESSION"'" 2>/dev/null'
until_ok "stop never marked the registry stopped" '[ "$(python3 -c "
import json;print(json.load(open(\"'"$T"'/.delivery-machine/registry.json\"))[\"'"$PROJ"'\"].get(\"state\",\"\"))")" = stopped ]'
[ "$(reg dir)" = "$P" ] || fail "the registry entry lost its dir — it must be marked, never rewritten"
[ "$(reg port)" = "$PORT" ] || fail "the registry entry lost its port"

# 4. the page has the control, and it is wired to this route
UI="$HERE/../../plugin-mc/mission-control"
grep -q 'id="stopBtn"'  "$UI/index.html" || fail "no stop button in the top bar"
grep -q 'id="pauseBtn"' "$UI/index.html" || fail "no pause button in the top bar"
grep -q 'id="handoffAge"' "$UI/index.html" || fail "the top bar does not show the handoff's age"
grep -q '"/api/machine"' "$UI/js/boot.js" || fail "the buttons do not call /api/machine"
grep -q 'no handoff yet' "$UI/js/boot.js" || fail "the top bar does not say when there is no handoff"
grep -q 'detached: true' "$UI/server.js" || fail "dm-stop.sh is not started detached — it will die with the session it kills"

echo "PASS test_cockpit_machine"
