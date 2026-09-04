#!/usr/bin/env bash
# PreCompact hook — snapshot hard state into .delivery/HANDOFF.md before the
# conversation is summarized. Silent no-op outside a Janus project.
set -uo pipefail
[ -d .delivery ] || exit 0
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])" 2>/dev/null || basename "$PWD")
{
  echo "# HANDOFF — $PROJ — $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "## Git"
  echo '```'
  git branch --show-current 2>/dev/null
  git status --short 2>/dev/null | head -30
  git log --oneline -5 2>/dev/null
  echo '```'
  echo
  echo "## Services (tmux dm-$PROJ)"
  echo '```'
  tmux list-windows -t "dm-$PROJ" -F '#W  #{pane_current_command}' 2>/dev/null || echo "machine not running"
  echo '```'
  echo
  echo "## Planning state"
  ls -t .planning 2>/dev/null | head -10 || echo "no .planning/"
  echo
  echo "## Inbox (pending operator/phone/voice items)"
  ls .delivery/inbox 2>/dev/null || echo "empty"
  echo
  echo "## Last runs"
  tail -5 .delivery/runs.jsonl 2>/dev/null || echo "none"
  echo
  # The open checklist is the single most useful thing to carry across a context boundary: it says
  # what was being done and what still has to be proven, which prose summaries lose first.
  echo "## Open checklists (unfinished work, with what would prove each item)"
  if ls .delivery/checklist/*.json >/dev/null 2>&1; then
    python3 - <<'PY'
import glob, json, os
open_any = False
for f in sorted(glob.glob(".delivery/checklist/*.json"), key=os.path.getmtime, reverse=True):
    try: d = json.load(open(f))
    except Exception: continue
    items = d.get("items") or []
    if items and all(i.get("done") for i in items): continue      # finished; not a resume point
    open_any = True
    print(f"\n**{d.get('slice')}** — {d.get('intent','')}")
    if d.get("gated"): print(f"  gated: {', '.join(d.get('triggers') or []) or 'yes'} · approved: {d.get('approved_at') or 'NOT YET'}")
    for i in items:
        print(f"  [{'x' if i.get('done') else ' '}] {i.get('text','')}  →  {i.get('proof','')}")
if not open_any: print("none open")
PY
  else
    echo "none open"
  fi
  echo
  # Knowledge writes are otherwise invisible: three of the four locations are in git, but a write to
  # a memory directory outside any repo leaves this log as its only trace.
  echo "## Knowledge touched (newest first)"
  if [ -s .delivery/knowledge.log ]; then
    tail -40 .delivery/knowledge.log | awk -F'\t' '{c[$2]++; last[$2]=$1} END {for (p in c) printf "- %s  (%d edit%s, last %s)\n", p, c[p], (c[p]>1?"s":""), last[p]}' | sort
  else
    echo "none this session"
  fi
  echo
  echo "_Resume: read this, then continue the current step. Rules live in the /dm skill._"
} > .delivery/HANDOFF.md
exit 0
