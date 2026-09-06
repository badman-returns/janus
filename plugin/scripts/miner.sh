#!/usr/bin/env bash
# 02:00 miner: promote yesterday's captured sessions into wiki pages. Cognee's plugin already holds
# the raw turns; this job turns them into corrections, decisions and patterns the operator can read.
source "$(dirname "$0")/job-guard.sh"
set -uo pipefail
BRAIN=$(cat "$HOME/.delivery-machine/brain"); cd "$BRAIN"
export CLAUDE_CONFIG_DIR="$HOME/.claude-tsg" COGNEE_PLUGIN_DATASET=fleet
Y=$(date -v-1d +%F 2>/dev/null || date -d yesterday +%F)
claude -p "/concierge Mine yesterday ($Y). For each dataset fleet, clinic-app, platform-app, janus run /cognee-memory:cognee-search for 'corrections the operator gave on $Y', 'decisions made on $Y', 'questions the operator asked on $Y'. Never query shop-web or alt. Write or update: wiki/method/corrections.md (one bullet per correction, quoted, with the machine and date; group repeats), wiki/self/calendar/$Y.md (which machines, which slices, how many turns, first and last activity time from runs.jsonl), wiki/decisions/registry.md via python3 tools/registry.py. Update index.md, append to log.md as '## [$Y] ingest | miner'. Run python3 tools/lint.py and fix what it reports. Commit nothing." >> .delivery/pickup.log 2>&1
