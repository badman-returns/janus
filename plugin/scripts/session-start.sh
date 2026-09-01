#!/usr/bin/env bash
# SessionStart hook — inject handoff + machine status into new/compacted
# sessions. Silent no-op outside a delivery-machine project.
set -uo pipefail
[ -d .delivery ] || exit 0
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])" 2>/dev/null || basename "$PWD")
echo "DELIVERY MACHINE PROJECT ($PROJ). Operate per the /dm skill: approval gates, agents for real work, services in tmux only, proof before done."
if tmux has-session -t "dm-$PROJ" 2>/dev/null; then
  echo "Machine RUNNING — windows: $(tmux list-windows -t "dm-$PROJ" -F '#W' | tr '\n' ' ')"
else
  echo "Machine NOT running — start with: bash \"\$(dirname of plugin)/scripts/orchestrator.sh\" or ask /dm to start it."
fi
if [ -s .delivery/HANDOFF.md ]; then
  echo "--- HANDOFF from previous context ---"
  cat .delivery/HANDOFF.md
fi
PENDING=$(ls .delivery/inbox 2>/dev/null | wc -l | tr -d ' ')
[ "$PENDING" != "0" ] && echo "INBOX: $PENDING pending item(s) in .delivery/inbox — process them first."
exit 0
