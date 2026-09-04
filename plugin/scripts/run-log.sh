#!/usr/bin/env bash
# The ONLY writer of .delivery/runs.jsonl. `done` is refused unless the agent is
# dm-verifier and proof/<slice>/README.md is newer than the slice's newest commit
# (proof-fresh.sh) — a refused done means the slice is not done.
# Usage: run-log.sh <agent> <slice> <status> <note…>   (from the project root)
# Statuses: dispatched|working|built|reviewed|fixed|failed|done. `dispatched` means an agent has
# been handed this slice and is running now — logged BEFORE the work, so an in-flight agent is
# visible; every other status is logged after. Refusal = exit 2, nothing written.
set -uo pipefail
[ -d .delivery ] || exit 1
AGENT=${1:?agent}; SLICE=${2:?slice}; STATUS=${3:?status}; shift 3
# Agent names were unchecked, so the ledger accumulated whatever was typed. The rule is the
# one already in use: the orchestrator itself, or a dm-<role> agent. That admits the roles a
# project adds (dm-scenario-writer) while still rejecting a typo like "builder" or "dm_builder",
# which would otherwise sit in the ledger as a distinct actor forever.
case "$AGENT" in
  orchestrator) ;;
  # [:lower:] not [a-z]: under a UTF-8 locale the range collates and lets "dm-Builder" through
  dm-*) case "$AGENT" in *[![:lower:][:digit:]-]*) echo "run-log: bad agent '$AGENT' (lowercase, digits and - only)" >&2; exit 2 ;; esac ;;
  *) echo "run-log: unknown agent '$AGENT' (orchestrator, or dm-<role>)" >&2; exit 2 ;;
esac
case "$STATUS" in
  dispatched|working|built|reviewed|fixed|failed|done) ;;
  *) echo "run-log: unknown status '$STATUS' (dispatched|working|built|reviewed|fixed|failed|done)" >&2; exit 2 ;;
esac
if [ "$STATUS" = done ]; then
  [ "$AGENT" = dm-verifier ] || { echo "run-log: only dm-verifier may log done, not $AGENT" >&2; exit 2; }
  bash "$(dirname "$0")/proof-fresh.sh" "$SLICE" >/dev/null || exit 2
fi
DM_AGENT=$AGENT DM_SLICE=$SLICE DM_STATUS=$STATUS DM_NOTE="$*" python3 - <<'EOF2'
import json, os, time
e = os.environ
line = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "agent": e["DM_AGENT"],
        "slice": e["DM_SLICE"], "status": e["DM_STATUS"], "note": e.get("DM_NOTE", "")}
with open(".delivery/runs.jsonl", "a") as f: f.write(json.dumps(line) + "\n")
EOF2
