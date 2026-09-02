#!/usr/bin/env bash
# Open a new Claude session INSIDE the machine (window claude, claude-2, …) so
# mission control gets a terminal tile for it. Prints the window name.
# Usage: dm-session.sh [claude args…]   (from project root)
set -euo pipefail
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])")
CFG=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('claude_config_dir') or '')")
SESSION="dm-$PROJ"
tmux has-session -t "$SESSION" 2>/dev/null || { echo "machine not running — run orchestrator.sh first" >&2; exit 1; }
W=claude; n=1
while tmux list-windows -t "$SESSION" -F '#W' | grep -qx "$W"; do n=$((n+1)); W="claude-$n"; done
q(){ printf "%q" "$1"; }
CMD="${CFG:+CLAUDE_CONFIG_DIR=$(q "${CFG/#\~/$HOME}") }${DM_CLAUDE_BIN:-claude}"
for a in "$@"; do CMD="$CMD $(q "$a")"; done
tmux new-window -t "$SESSION" -n "$W" -c "$PWD"
tmux send-keys -t "$SESSION:$W" "$CMD" Enter
echo "$W"
