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

# headless claude must run on the account the plugin is installed under
CFG_DIR=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('claude_config_dir') or '')")
if [ -n "$CFG_DIR" ]; then
  export CLAUDE_CONFIG_DIR="${CFG_DIR/#\~/$HOME}"
  echo "headless claude uses CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
fi

echo "pickup watcher running — polling .delivery/inbox every ${POLL}s (Ctrl-C to stop)"
while true; do
  # unhandled = note-*/reply-* the orchestrator hasn't consumed
  PENDING=$(ls .delivery/inbox/ 2>/dev/null | grep -E '^(note|reply)-' | wc -l | tr -d ' ')
  if [ "$PENDING" != "0" ] && [ ! -f "$LOCK" ]; then
    # a live session always takes priority — never dispatch beside one
    if ! bash "$(dirname "${BASH_SOURCE[0]}")/is-live.sh"; then
      echo "$(date '+%H:%M:%S') — $PENDING inbox item(s), no live session; dispatching headless orchestrator"
      touch "$LOCK"
      # snapshot BEFORE dispatch so notes arriving mid-run are not swallowed
      HANDLING=$(ls .delivery/inbox/ 2>/dev/null | grep -E '^(note|reply)-' || true)
      if command -v claude >/dev/null 2>&1; then
        claude -p "/dm process the pending items in .delivery/inbox and reply, then stop" >> .delivery/pickup.log 2>&1 || true
        # /dm deletes what it answers; anything still on disk was NOT consumed
        # (crashed or errored run) and would be re-dispatched forever — park it
        # and say so, because a silent drop is worse than a loud one
        mkdir -p .delivery/inbox/handled
        printf '%s\n' "$HANDLING" | while read -r f; do
          [ -n "$f" ] && [ -f ".delivery/inbox/$f" ] || continue
          mv -f ".delivery/inbox/$f" .delivery/inbox/handled/ 2>/dev/null &&
            echo "$(date '+%H:%M:%S') — UNCONSUMED after run, parked in inbox/handled/: $f" >> .delivery/pickup.log
        done
      else
        echo "$(date '+%H:%M:%S') — claude CLI not found; leaving items for a live session" >> .delivery/pickup.log
      fi
      rm -f "$LOCK"
    fi
  fi
  sleep "$POLL"
done
