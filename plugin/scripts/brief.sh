#!/usr/bin/env bash
# 07:00 brief: what waits at every gate, what moved since yesterday, what the mirror sees. Written
# by a headless concierge into the fleet outbox so the feed sends it. Voice too if ~/.brain/brief.voice exists.
HERE="$(cd "$(dirname "$0")" && pwd)"   # absolute: this job cd's into the brain repo two lines down
source "$HERE/job-guard.sh"
set -uo pipefail
# no pointer means `cd ""` — a silent no-op that would run the whole job in launchd's cwd
BRAIN=$(cat "$HOME/.delivery-machine/brain" 2>/dev/null)
[ -n "$BRAIN" ] || { echo "$(date +%FT%T) brief: no brain pointer in $HOME/.delivery-machine/brain" >> "$HOME/.brain/jobs.log"; exit 1; }
cd "$BRAIN" || { echo "$(date +%FT%T) brief: brain $BRAIN is not a directory" >> "$HOME/.brain/jobs.log"; exit 1; }
export CLAUDE_CONFIG_DIR="$HOME/.claude-tsg" COGNEE_PLUGIN_DATASET=fleet
MS=$(python3 -c "import time;print(int(time.time()*1000))")
${DM_CLAUDE_BIN:-claude} -p "/concierge Write the morning brief. Read fleet-status.sh, inflight.sh, every machine's .delivery/inbox for gates, runs.jsonl lines since yesterday 07:00, and wiki/self for the latest mirror. Format: gates waiting first (machine, slice, what to decide); then what finished, with proof paths; then three lines of mirror (hours worked yesterday from the ledgers, anything after 01:00, anything unanswered for more than a day). Phone-readable, under 40 lines, no tables. Written as what happened and what he must decide, in full sentences, machine names as words; no ledger jargon, no file paths unless he needs one to act. Write it to .delivery/outbox/$MS-brief.md and nothing else." >> .delivery/pickup.log 2>&1
RC=$?
if [ $RC -ne 0 ]; then
  # a missing or rate-limited `claude` used to end here in silence; now the log and the phone both hear it
  echo "$(date +%FT%T) brief: claude failed rc=$RC (see .delivery/pickup.log)" >> "$HOME/.brain/jobs.log"
  echo "the morning brief did not run: claude exited $RC" > ".delivery/outbox/$MS-brief-failed.txt"
  exit $RC
fi
# claude exiting 0 having written nothing — a refused tool call, a truncated answer — used to look
# exactly like a quiet morning. The artefact is the proof the job ran, not the exit code.
if [ ! -s ".delivery/outbox/$MS-brief.md" ]; then
  echo "$(date +%FT%T) brief: claude wrote nothing (see .delivery/pickup.log)" >> "$HOME/.brain/jobs.log"
  echo "the morning brief produced nothing" > ".delivery/outbox/$MS-brief-failed.txt"
  exit 1
fi
if [ -e "$HOME/.brain/brief.voice" ] && [ -s ".delivery/outbox/$MS-brief.md" ]; then
  bash "$HERE/tts-ogg.sh" "$(head -c 1200 ".delivery/outbox/$MS-brief.md")" ".delivery/outbox/$MS-brief.ogg" >/dev/null
  # only caption a voice file that actually rendered, or the feed sends a caption with nothing behind it
  [ -s ".delivery/outbox/$MS-brief.ogg" ] && echo "morning brief" > ".delivery/outbox/$MS-brief.ogg.caption"
fi
[ -s ".delivery/outbox/$MS-brief.md" ] && echo "morning brief" > ".delivery/outbox/$MS-brief.md.caption"
exit 0
