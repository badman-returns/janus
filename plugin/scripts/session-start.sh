#!/usr/bin/env bash
# SessionStart hook — inject handoff + machine status into new/compacted
# sessions. Silent no-op outside a Janus project.
set -uo pipefail
[ -d .delivery ] || exit 0
rm -f .delivery/.touched   # gate-check.sh counts files touched THIS session, not ever
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])" 2>/dev/null || basename "$PWD")
echo "JANUS PROJECT ($PROJ). Operate per the /dm skill: approval gates, agents for real work, services in tmux only, proof before done."
if tmux has-session -t "dm-$PROJ" 2>/dev/null; then
  echo "Machine RUNNING — windows: $(tmux list-windows -t "dm-$PROJ" -F '#W' | tr '\n' ' ')"
else
  echo "Machine NOT running — start with: bash \"\$(dirname of plugin)/scripts/orchestrator.sh\" or ask /dm to start it."
fi
INSIDE=""
if [ -n "${TMUX:-}" ]; then   # ask about our own pane; a bare display-message answers for the newest client (often a ttyd view)
  G=$(tmux display-message -p -t "${TMUX_PANE:-}" '#{session_group}' 2>/dev/null); [ -n "$G" ] || G=$(tmux display-message -p -t "${TMUX_PANE:-}" '#S' 2>/dev/null)
  case "$G" in dm-*) INSIDE=1 ;; esac
fi
if [ -z "$INSIDE" ]; then
  echo "NOTE: this session runs OUTSIDE the machine's tmux — mission control cannot show it. Next time start with: bash <plugin>/scripts/dm.sh"
fi
if [ -s .delivery/HANDOFF.md ]; then
  echo "--- HANDOFF from previous context ---"
  cat .delivery/HANDOFF.md
fi
PENDING=$(ls .delivery/inbox 2>/dev/null | wc -l | tr -d ' ')
[ "$PENDING" != "0" ] && echo "INBOX: $PENDING pending item(s) in .delivery/inbox — process them first."

# An unfinished checklist is a resume point, and saying so here is what stops a fresh session
# starting something new while the last thing is still half-proven.
if ls .delivery/checklist/*.json >/dev/null 2>&1; then
  python3 - <<'PY' 2>/dev/null
import glob, json, os
for f in sorted(glob.glob(".delivery/checklist/*.json"), key=os.path.getmtime, reverse=True):
    try: d = json.load(open(f))
    except Exception: continue
    items = d.get("items") or []
    left = [i for i in items if not i.get("done")]
    if not items or not left: continue
    print(f"OPEN CHECKLIST: {d.get('slice')} — {len(items)-len(left)}/{len(items)} done; next: {left[0].get('text','')}"
          + ("" if d.get("approved_at") or not d.get("gated") else "  [GATED, NOT APPROVED]"))
PY
fi
exit 0
