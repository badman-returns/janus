#!/usr/bin/env bash
# Weekly wiki lint (Sunday 08:00): dangling links, orphans, claims without provenance. Defects go to
# the phone with a caption; a clean week says nothing, so silence means the wiki is healthy.
source "$(dirname "$0")/job-guard.sh"
set -uo pipefail
BRAIN=$(cat "$HOME/.delivery-machine/brain"); cd "$BRAIN"
OUT=".delivery/outbox/$(date +%s)-lint.txt"
python3 tools/lint.py > "$OUT" 2>&1 && rm -f "$OUT" || echo "wiki lint found defects" > "$OUT.caption"
exit 0
