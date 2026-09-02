#!/usr/bin/env bash
# SessionStart hook — inject handoff + machine status into new/compacted
# sessions. Silent no-op outside a Janus project.
set -uo pipefail
[ -d .delivery ] || exit 0
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
exit 0
