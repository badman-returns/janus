#!/usr/bin/env bash
# Always-on pickup — when the operator leaves inbox items (from dashboard/phone)
# and no orchestrator is actively working, spawn a headless Claude to process
# them, so notes get answered even with no live session. Runs as its own tmux
# window. Poll interval + headless command are configurable.
# Usage: watch.sh   (from project root; loops forever)
set -uo pipefail
[ -d .delivery ] || { echo "not a dm project"; exit 1; }
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])")
LOCK=".delivery/.pickup.lock"
POLL=${DM_WATCH_POLL:-20}
echo "pickup watcher running — polling .delivery/inbox every ${POLL}s (Ctrl-C to stop)"
while true; do
  # unhandled = note-*/reply-* the orchestrator hasn't consumed
  PENDING=$(ls .delivery/inbox/ 2>/dev/null | grep -E '^(note|reply)-' | wc -l | tr -d ' ')
  if [ "$PENDING" != "0" ] && [ ! -f "$LOCK" ]; then
    # skip if a run started in the last 90s (a live session is probably on it)
    RECENT=$(python3 -c "
import json,time,os
p='.delivery/runs.jsonl'
if os.path.exists(p):
    ls=[l for l in open(p) if l.strip()]
    if ls:
        import datetime
        try:
            t=json.loads(ls[-1]).get('ts','')
            dt=datetime.datetime.fromisoformat(t.replace('Z','+00:00'))
            print(1 if (datetime.datetime.now(datetime.timezone.utc)-dt).total_seconds()<90 else 0)
        except Exception: print(0)
    else: print(0)
else: print(0)")
    if [ "$RECENT" = "0" ]; then
      echo "$(date '+%H:%M:%S') — $PENDING inbox item(s), no live session; dispatching headless orchestrator"
      touch "$LOCK"
      if command -v claude >/dev/null 2>&1; then
        claude -p "/dm process the pending items in .delivery/inbox and reply, then stop" >> .delivery/pickup.log 2>&1 || true
      else
        echo "$(date '+%H:%M:%S') — claude CLI not found; leaving items for a live session" >> .delivery/pickup.log
      fi
      rm -f "$LOCK"
    fi
  fi
  sleep "$POLL"
done
