#!/usr/bin/env bash
# Weekly wiki lint (Sunday 08:00): dangling links, orphans, claims without provenance. Defects go to
# the phone with a caption; a clean week says nothing, so silence means the wiki is healthy.
source "$(dirname "$0")/job-guard.sh"
set -uo pipefail
# no pointer means `cd ""` — a silent no-op that would run the whole job in launchd's cwd
BRAIN=$(cat "$HOME/.delivery-machine/brain" 2>/dev/null)
[ -n "$BRAIN" ] || { echo "$(date +%FT%T) lint: no brain pointer in $HOME/.delivery-machine/brain" >> "$HOME/.brain/jobs.log"; exit 1; }
cd "$BRAIN" || { echo "$(date +%FT%T) lint: brain $BRAIN is not a directory" >> "$HOME/.brain/jobs.log"; exit 1; }
OUT=".delivery/outbox/$(date +%s)-lint.txt"
python3 tools/lint.py > "$OUT" 2>&1 && rm -f "$OUT" || echo "wiki lint found defects" > "$OUT.caption"
exit 0
