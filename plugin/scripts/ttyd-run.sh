#!/usr/bin/env bash
# Run ttyd under a watchdog. ttyd 1.7.7 on macOS never closes the pty master
# after a client's child exits, so every closed tile leaks one of the 511 ptys
# and the whole box eventually cannot open a terminal. This restarts ttyd once
# the leak builds up: at once when nobody is connected (invisible), or forced
# past a hard cap (tiles reconnect on their own in about a second).
# ponytail: restart-on-leak; drop this once ttyd releases masters on macOS.
# Usage: ttyd-run.sh <ttyd args…>
set -uo pipefail
SOFT=${DM_TTYD_SOFT:-20}; HARD=${DM_TTYD_HARD:-150}; POLL=${DM_TTYD_POLL:-30}
while true; do
  ttyd "$@" & PID=$!
  while kill -0 "$PID" 2>/dev/null; do
    sleep "$POLL"
    LEAK=$(lsof -p "$PID" 2>/dev/null | grep -c '/dev/ptmx')
    CLIENTS=$(pgrep -P "$PID" | wc -l | tr -d ' ')
    if { [ "$CLIENTS" = 0 ] && [ "$LEAK" -gt "$SOFT" ]; } || [ "$LEAK" -gt "$HARD" ]; then
      echo "$(date '+%H:%M:%S') — ttyd holds $LEAK pty masters for $CLIENTS client(s); restarting to free them"
      kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
    fi
  done
  sleep 1
done
