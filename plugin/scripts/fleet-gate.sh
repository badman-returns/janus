#!/usr/bin/env bash
# Answer the newest gate (or ask) of a machine the way the dashboard does: a reply-* file whose
# first line names the gate, then APPROVE or REJECT: <note>; the gate file is removed. A note on an
# APPROVE rides along as `APPROVE — <note>`, so the operator's ruling reaches the orchestrator that
# records it. `latest` in place of a machine answers the newest gate on *any* registered machine —
# the phone's "approve latest" (a machine actually named `latest` is shadowed by it).
# `--re <gate file>` names the card being answered: the feed card carries its own filename, and with
# two cards open on one machine the newest is not the one the operator was shown.
# Usage: fleet-gate.sh <machine>|latest APPROVE|REJECT [--re <gate file>] [note]
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJ=${1:?project}; VERDICT=$(printf %s "${2:?APPROVE|REJECT}" | tr '[:lower:]' '[:upper:]'); shift 2
RE=""; [ "${1:-}" = --re ] && { RE=${2:?--re needs a gate file name}; shift 2; }
NOTE="${*:-}"
# the verdict is checked before anything is read, so a typo cannot look like "no gate waiting";
# the gate card tells the operator to say `approve <proj>`, so case must not matter
case "$VERDICT" in
  APPROVE) BODY="APPROVE${NOTE:+ — $NOTE}" ;;
  REJECT)  BODY="REJECT: ${NOTE:-no reason given}" ;;
  *) echo "fleet-gate: verdict must be APPROVE or REJECT" >&2; exit 1 ;;
esac
if [ "$PROJ" = latest ]; then
  [ -z "$RE" ] || { echo "fleet-gate: --re names a card on one machine, not with latest" >&2; exit 1; }
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
  if [ -n "$RE" ]; then
    # a card name arrives from the phone with the machine name: it stays a name, never a path
    case "$RE" in ""|*/*|*[!A-Za-z0-9._-]*) echo "fleet-gate: bad card name" >&2; exit 1 ;; esac
    G="$DIR/.delivery/inbox/$RE"
    [ -f "$G" ] || { echo "no card $RE waiting in $PROJ" >&2; exit 2; }
  else
    W=$(ls -t "$DIR"/.delivery/inbox/gate-*.txt "$DIR"/.delivery/inbox/ask-*.txt 2>/dev/null) || true
    N=$(printf '%s\n' "${W:-}" | grep -c . ) || true
    [ "$N" -ge 1 ] || { echo "no gate waiting in $PROJ" >&2; exit 2; }
    # two cards open and none named: the newest is not necessarily the one the operator was shown,
    # and approving a plan he never read is the thing the two gates exist to prevent
    if [ "$N" -gt 1 ]; then
      { echo "fleet-gate: $N cards wait on $PROJ — answer one with --re <card>:"
        printf '%s\n' "$W" | while IFS= read -r f; do echo "  $(basename "$f")"; done; } >&2
      exit 3
    fi
    G=$W
  fi
fi
GN=$(basename "$G"); MS=$(python3 -c "import time;print(int(time.time()*1000))")
printf 'RE: %s\n%s\n' "$GN" "$BODY" > "$DIR/.delivery/inbox/reply-$MS-$(echo "$GN" | tr '.' '-').txt"
# the history the next round is read against: server.js's writeInbox appends the gate body and the
# reply to .delivery/threads/<gate>.md before deleting the gate, and an answer from the phone must
# not silently skip it
case "$GN" in gate-*)
  TS=$(date -u +%FT%TZ); mkdir -p "$DIR/.delivery/threads"
  printf '## %s · gate\n\n%s\n\n## %s · reply\n\n%s\n\n' \
    "$TS" "$(cat "$G")" "$TS" "$BODY" >> "$DIR/.delivery/threads/${GN%.txt}.md" ;;
esac
rm -f "$G"
echo "$VERDICT → $PROJ ($GN)"
