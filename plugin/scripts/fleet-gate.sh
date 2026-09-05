#!/usr/bin/env bash
# Answer the newest gate (or ask) of a machine the way the dashboard does: a reply-* file whose
# first line names the gate, then APPROVE or REJECT: <note>; the gate file is removed. A note on an
# APPROVE rides along as `APPROVE — <note>`, so the operator's ruling reaches the orchestrator that
# records it. `latest` in place of a machine answers the newest gate on *any* registered machine —
# the phone's "approve latest" (a machine actually named `latest` is shadowed by it).
# Usage: fleet-gate.sh <machine>|latest APPROVE|REJECT [note]
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJ=${1:?project}; VERDICT=${2:?APPROVE|REJECT}; shift 2; NOTE="${*:-}"
# the verdict is checked before anything is read, so a typo cannot look like "no gate waiting"
case "$VERDICT" in
  APPROVE) BODY="APPROVE${NOTE:+ — $NOTE}" ;;
  REJECT)  BODY="REJECT: ${NOTE:-no reason given}" ;;
  *) echo "fleet-gate: verdict must be APPROVE or REJECT" >&2; exit 1 ;;
esac
if [ "$PROJ" = latest ]; then
  OUT=$(python3 - <<'EOF' 2>/dev/null
import json, os, glob
reg = json.load(open(os.path.expanduser("~/.delivery-machine/registry.json")))
waiting = [(p, f) for p, m in reg.items() for pat in ("gate-*.txt", "ask-*.txt")
           for f in glob.glob(f"{m.get('dir', '')}/.delivery/inbox/{pat}")]
if waiting:
    p, f = max(waiting, key=lambda pf: os.path.getmtime(pf[1])); print(f"{p}\t{f}")
EOF
) || true
  [ -n "$OUT" ] || { echo "fleet-gate: nothing waiting on any machine" >&2; exit 2; }
  PROJ=${OUT%%$'\t'*}; G=${OUT#*$'\t'}; DIR=$(dirname "$(dirname "$(dirname "$G")")")
else
  DIR=$(bash "$HERE/machine-dir.sh" "$PROJ" fleet-gate) || exit 1
  G=$(ls -t "$DIR"/.delivery/inbox/gate-*.txt "$DIR"/.delivery/inbox/ask-*.txt 2>/dev/null | head -1) || true
  [ -n "${G:-}" ] || { echo "no gate waiting in $PROJ" >&2; exit 2; }
fi
GN=$(basename "$G"); MS=$(python3 -c "import time;print(int(time.time()*1000))")
printf 'RE: %s\n%s\n' "$GN" "$BODY" > "$DIR/.delivery/inbox/reply-$MS-$(echo "$GN" | tr '.' '-').txt"
rm -f "$G"
echo "$VERDICT → $PROJ ($GN)"
