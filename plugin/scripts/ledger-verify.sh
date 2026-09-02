#!/usr/bin/env bash
# Re-derive the ledger's guarantees from what is on disk. PROTOCOL.md says runs.jsonl is
# "written only by run-log.sh", but nothing can stop a `>>` from an agent that has a shell —
# so this does not try to prevent that write, it makes it visible.
#
# Every line must be shaped the way run-log.sh shapes it, and every `done` must still hold:
# logged by dm-verifier, with proof at least as new as the slice's newest commit. A `done`
# appended out of band fails here even though it looked fine going in.
#
# Entries older than .delivery/ledger-baseline (one ISO timestamp) are summarised rather than
# listed: a ledger written before a rule existed cannot have broken it, and a tool that reports
# twenty unfixable lines every run is a tool nobody reads.
#
# Usage: ledger-verify.sh [--quiet] · ledger-verify.sh --accept [ISO-ts]   (from the project root)
# Exit 0 clean · 2 with one line per violation on stdout · 1 if there is no ledger.
set -uo pipefail
QUIET=""
if [ "${1:-}" = "--accept" ]; then
  [ -d .delivery ] || { echo "not a Janus project"; exit 1; }
  TS=${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
  echo "$TS" > .delivery/ledger-baseline
  echo "ledger-verify: entries at or before $TS are now treated as history"
  exit 0
fi
[ "${1:-}" = "--quiet" ] && QUIET=1
BASELINE=$(cat .delivery/ledger-baseline 2>/dev/null || echo "")
[ -d .delivery ] || { echo "not a Janus project"; exit 1; }
LEDGER=.delivery/runs.jsonl
[ -f "$LEDGER" ] || { [ -n "$QUIET" ] || echo "no ledger yet"; exit 0; }

HERE="$(cd "$(dirname "$0")" && pwd)"

# shape first, in one pass; proof freshness needs git and runs per done-line below
BAD=$(python3 - "$LEDGER" "$BASELINE" <<'PY'
import json, re, sys

BASELINE = sys.argv[2] if len(sys.argv) > 2 else ""
AGENT = re.compile(r"^(orchestrator|dm-[a-z0-9-]+)$")
STATUS = {"working", "built", "reviewed", "fixed", "failed", "done"}
FIELDS = {"ts", "agent", "slice", "status", "note"}

def out(n, msg, old):
    print(f"{n}\t{'OLD' if old else 'NEW'}:{msg}")

for n, raw in enumerate(open(sys.argv[1]), 1):
    if not raw.strip():
        continue
    try:
        r = json.loads(raw)
    except Exception:
        out(n, "line is not JSON — run-log.sh never writes that", False)
        continue
    old = bool(BASELINE) and str(r.get("ts", "")) <= BASELINE if isinstance(r, dict) else False
    if not isinstance(r, dict):
        out(n, "line is not an object", False)
        continue
    missing = FIELDS - set(r)
    if missing:
        out(n, f"missing field(s): {', '.join(sorted(missing))}", old)
    extra = set(r) - FIELDS
    if extra:
        out(n, f"unknown field(s): {', '.join(sorted(extra))}", old)
    if not AGENT.match(str(r.get("agent", ""))):
        out(n, f"agent {r.get('agent')!r} is not orchestrator or dm-<role>", old)
    if r.get("status") not in STATUS:
        out(n, f"status {r.get('status')!r} is not one run-log.sh accepts", old)
    elif r["status"] == "done" and r.get("agent") != "dm-verifier":
        out(n, f"done logged by {r.get('agent')!r} — only dm-verifier may", old)
    # a done line names a slice whose proof must still be fresh; checked outside
    if r.get("status") == "done" and r.get("agent") == "dm-verifier":
        print(f"{n}\t{'OLD' if old else 'NEW'}:CHECKPROOF\t{r.get('slice')}")
PY
)

VIOLATIONS=""; OLDCOUNT=0
while IFS=$'\t' read -r n tagged slice; do
  [ -n "$n" ] || continue
  age=${tagged%%:*}; msg=${tagged#*:}
  if [ "$msg" = "CHECKPROOF" ]; then
    why=$(bash "$HERE/proof-fresh.sh" "$slice" 2>&1 >/dev/null) && continue
    msg="done for '$slice' no longer holds — $why"
  fi
  if [ "$age" = OLD ]; then OLDCOUNT=$((OLDCOUNT+1)); continue; fi
  VIOLATIONS="${VIOLATIONS}  line $n: $msg"$'\n'
done <<< "$BAD"

if [ -n "$VIOLATIONS" ]; then
  echo "ledger-verify: $LEDGER has entries run-log.sh would not have written"
  printf '%s' "$VIOLATIONS"
  [ "$OLDCOUNT" -gt 0 ] && echo "  (plus $OLDCOUNT older than the baseline $BASELINE — history, not listed)"
  exit 2
fi
if [ -z "$QUIET" ]; then
  if [ "$OLDCOUNT" -gt 0 ]; then
    echo "ledger-verify: clean since $BASELINE ($OLDCOUNT older entries predate the rules, not listed)"
  else
    echo "ledger-verify: clean — every line is shaped like run-log.sh writes it, every done still has fresh proof"
  fi
fi
