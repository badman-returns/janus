#!/usr/bin/env bash
# The operator's front door: machine up, a fresh Claude inside it, attached.
# Usage: dm.sh [claude args…]   e.g. dm.sh --resume 8d83d973
set -euo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f .delivery/config.json ] || { echo "no .delivery/config.json — run /dm-init in Claude first"; exit 1; }
bash "$PLUGIN_ROOT/scripts/orchestrator.sh" --no-open >/dev/null
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])")
W=$(bash "$PLUGIN_ROOT/scripts/dm-session.sh" "$@")
unset TMUX   # allow attaching from inside another tmux
exec tmux attach -t "dm-$PROJ:$W"
