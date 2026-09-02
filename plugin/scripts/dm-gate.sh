#!/usr/bin/env bash
# Open Gate 2 for a slice: writes .delivery/inbox/gate-<slice>-proof.txt and
# pings the phone — but only when proof/<slice>/README.md is newer than the
# slice's newest commit (proof-fresh.sh). Stale or missing proof = exit 2 with
# the reason and no gate file: a gate that cannot fail is decoration.
# Usage: dm-gate.sh <slice>   (from the project root)
set -uo pipefail
[ -d .delivery ] || exit 1
SLICE=${1:?slice}
HERE=$(cd "$(dirname "$0")" && pwd)
BRANCH=$(bash "$HERE/proof-fresh.sh" "$SLICE") || exit 2
mkdir -p .delivery/inbox
{
  echo "GATE 2 — review proof for $SLICE"
  echo
  echo "branch: $BRANCH"
  echo "proof/$SLICE/:"
  ls -1 "proof/$SLICE" | sed 's/^/  /'
  echo
  echo "APPROVE / REJECT with note"
} > ".delivery/inbox/gate-$SLICE-proof.txt"
bash "$HERE/notify.sh" "GATE 2: $SLICE"
