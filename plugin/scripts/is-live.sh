#!/usr/bin/env bash
# Is a Claude session live in this project? Live = a hook heartbeat younger
# than DM_LIVE_SECS (default 120), or a claude* window open in the machine.
# runs.jsonl is NOT consulted: it only moves when an agent finishes, so a
# session thinking for five minutes looked dead and the watcher double-dispatched.
# Usage: is-live.sh   (from project root; exit 0 = live)
set -uo pipefail
[ -d .delivery ] || exit 1
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])" 2>/dev/null) || exit 1
if tmux list-windows -t "dm-$PROJ" -F '#W' 2>/dev/null | grep -q '^claude'; then exit 0; fi
python3 - "${DM_LIVE_SECS:-120}" <<'EOF'
import glob, json, sys, datetime
win = int(sys.argv[1]); now = datetime.datetime.now(datetime.timezone.utc)
for p in glob.glob(".delivery/agents/*.json"):
    try:
        ts = json.load(open(p)).get("ts", "")
        dt = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if (now - dt).total_seconds() < win: sys.exit(0)
    except Exception: pass
sys.exit(1)
EOF
