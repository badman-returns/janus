#!/usr/bin/env bash
# The fleet switcher names the machine you are on and flags the ones that want you, so the
# waiting count it reads from /api/state must agree with /api/fleet. Those were two separate
# copies of the same filter; this pins them together and pins what counts as "waiting":
# gates and asks do, the operator's own reply-/note- files do not.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SRV="$HERE/../../plugin-mc/mission-control/server.js"
T=$(mktemp -d); PORT=5598; PID=""
trap '[ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_fleet_waiting: $1"; exit 1; }

# two projects, only one of which wants the operator
mkdir -p "$T/here/.delivery/inbox" "$T/there/.delivery/inbox"
echo '{"project":"here"}'  > "$T/here/.delivery/config.json"
echo '{"project":"there"}' > "$T/there/.delivery/config.json"

: > "$T/there/.delivery/inbox/gate-login.txt"          # counts
: > "$T/there/.delivery/inbox/ask-1-pdf.txt"           # counts
: > "$T/there/.delivery/inbox/reply-1-pdf.txt"         # operator wrote it — must not count
: > "$T/there/.delivery/inbox/note-2-thought.txt"      # ditto
: > "$T/there/.delivery/inbox/.gitkeep"                # ditto

# the server reads the registry from $HOME, so point HOME at the sandbox
mkdir -p "$T/.delivery-machine"
cat > "$T/.delivery-machine/registry.json" <<JSON
{ "here":  { "dir": "$T/here",  "session": "dm-none-a", "port": 5501, "ttyd_port": 5601 },
  "there": { "dir": "$T/there", "session": "dm-none-b", "port": 5502, "ttyd_port": 5602 } }
JSON

HOME="$T" node "$SRV" --port $PORT --project "$T/here" --session dm-none >/dev/null 2>&1 & PID=$!; disown
for i in $(seq 1 40); do curl -sf "localhost:$PORT/api/state" >/dev/null && break; sleep 0.25; done
curl -sf "localhost:$PORT/api/state" >/dev/null || fail "server did not come up on $PORT"

curl -sf "localhost:$PORT/api/state" > "$T/state.json" || fail "/api/state failed"
curl -sf "localhost:$PORT/api/fleet" > "$T/fleet.json" || fail "/api/fleet failed"

python3 - "$T/state.json" "$T/fleet.json" <<'EOF' || fail "assertions"
import json, sys
state = json.load(open(sys.argv[1]))
fleet = json.load(open(sys.argv[2]))

sf = {f["project"]: f for f in state["fleet"]}
ff = {f["project"]: f for f in fleet}
assert set(sf) == set(ff) == {"here", "there"}, (list(sf), list(ff))

# the switcher can only flag other machines if /api/state carries the count at all
for p in sf:
    assert "waiting" in sf[p], f"/api/state fleet entry {p} has no waiting count"
    assert sf[p]["waiting"] == ff[p]["waiting"], \
        f"{p}: /api/state says {sf[p]['waiting']}, /api/fleet says {ff[p]['waiting']}"

# gates and asks count; reply-, note- and dotfiles are the operator's own writing
assert sf["there"]["waiting"] == 2, f"there should have 2 waiting, got {sf['there']['waiting']}"
assert sf["here"]["waiting"] == 0, f"here should have 0 waiting, got {sf['here']['waiting']}"

# the switcher labels itself with the current project, so state must say which one that is
assert state["project"] == "here", state.get("project")
EOF

# the label is the machine name, never a count of machines
grep -q 'fleetName").innerHTML = esc(s.project' "$HERE/../../plugin-mc/mission-control/js/boot.js" \
  || fail "fleet switcher should be labelled with the current project"
grep -q '"fleet · " +' "$HERE/../../plugin-mc/mission-control/js/boot.js" \
  && fail "fleet switcher is still labelled with a machine count"

echo "PASS test_fleet_waiting"
