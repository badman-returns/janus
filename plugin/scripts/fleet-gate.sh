#!/usr/bin/env bash
# Answer the newest gate (or ask) of a machine the way the dashboard does: a reply-* file whose
# first line names the gate, then APPROVE or REJECT: <note>; the gate file is removed.
# Usage: fleet-gate.sh <project> APPROVE|REJECT [note]
set -euo pipefail
PROJ=${1:?project}; VERDICT=${2:?APPROVE|REJECT}; shift 2; NOTE="${*:-}"
DIR=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.delivery-machine/registry.json')))['$PROJ']['dir'])")
G=$(ls -t "$DIR"/.delivery/inbox/gate-*.txt "$DIR"/.delivery/inbox/ask-*.txt 2>/dev/null | head -1) || true
[ -n "${G:-}" ] || { echo "no gate waiting in $PROJ" >&2; exit 2; }
GN=$(basename "$G"); MS=$(python3 -c "import time;print(int(time.time()*1000))")
case "$VERDICT" in
  APPROVE) BODY="APPROVE" ;;
  REJECT)  BODY="REJECT: ${NOTE:-no reason given}" ;;
  *) echo "verdict must be APPROVE or REJECT" >&2; exit 1 ;;
esac
printf 'RE: %s\n%s\n' "$GN" "$BODY" > "$DIR/.delivery/inbox/reply-$MS-$(echo "$GN" | tr '.' '-').txt"
rm -f "$G"
echo "$VERDICT → $PROJ ($GN)"
