#!/usr/bin/env bash
# 02:00 miner: promote yesterday's captured sessions into wiki pages. Cognee's plugin already holds
# the raw turns; this job turns them into corrections, decisions and patterns the operator can read.
source "$(dirname "$0")/job-guard.sh"
set -uo pipefail
# Cognee holds the captured sessions this job mines. Until its plugin is installed there is nothing
# to mine, so say so once in the log and stop — an empty run would only burn a headless seat.
ls -d "$HOME"/.claude-tsg/plugins/cache/*/cognee-memory/*/ >/dev/null 2>&1 || {
  echo "$(date +%FT%T) miner: cognee-memory plugin not installed, nothing to mine yet" >> "$HOME/.brain/jobs.log"
  exit 0; }
BRAIN=$(cat "$HOME/.delivery-machine/brain"); cd "$BRAIN"
export CLAUDE_CONFIG_DIR="$HOME/.claude-tsg" COGNEE_PLUGIN_DATASET=fleet
MS=$(python3 -c "import time;print(int(time.time()*1000))")
Y=$(date -v-1d +%F 2>/dev/null || date -d yesterday +%F)
claude -p "/concierge Mine yesterday ($Y). For each dataset fleet, clinic-app, platform-app, janus run /cognee-memory:cognee-search for 'corrections the operator gave on $Y', 'decisions made on $Y', 'questions the operator asked on $Y'. Never query shop-web or alt. Write or update: wiki/method/corrections.md (one bullet per correction, quoted, with the machine and date; group repeats), wiki/self/calendar/$Y.md (which machines, which slices, how many turns, first and last activity time from runs.jsonl), wiki/decisions/registry.md via python3 tools/registry.py. Update index.md, append to log.md as '## [$Y] ingest | miner'. Run python3 tools/lint.py and fix what it reports. Commit nothing." >> .delivery/pickup.log 2>&1
RC=$?
if [ $RC -ne 0 ]; then
  # a missing or rate-limited `claude` used to end here in silence; now the log and the phone both hear it
  echo "$(date +%FT%T) miner: claude failed rc=$RC (see .delivery/pickup.log)" >> "$HOME/.brain/jobs.log"
  echo "last night's miner did not run: claude exited $RC" > ".delivery/outbox/$MS-miner-failed.txt"
  exit $RC
fi
