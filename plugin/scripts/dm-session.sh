#!/usr/bin/env bash
# Open a new Claude session INSIDE the machine (window claude, claude-2, …) so
# mission control gets a terminal tile for it. Prints the window name.
# Usage: dm-session.sh [claude args…]   (from project root)
set -euo pipefail
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])")
CFG=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('claude_config_dir') or '')")
DS=$(python3 -c "import json;c=json.load(open('.delivery/config.json'));print(c.get('memory_dataset') or c['project'])")
SESSION="dm-$PROJ"
TM="tmux ${TMUX_SOCK:-}"
$TM has-session -t "$SESSION" 2>/dev/null || { echo "machine not running — run orchestrator.sh first" >&2; exit 1; }
W=claude; n=1
while $TM list-windows -t "$SESSION" -F '#W' | grep -qx "$W"; do n=$((n+1)); W="claude-$n"; done
q(){ printf "%q" "$1"; }
PRE=""   # keychain secrets in the session too, when the config asks: ccgram's hooks want the bot token
if [ "$(python3 -c "import json;print(bool(json.load(open('.delivery/config.json')).get('secrets')))")" = True ]; then
  PRE="eval \"\$(bash '$(dirname "$0")/secrets-env.sh')\"; "
fi
CMD="${PRE}COGNEE_PLUGIN_DATASET=$(q "$DS") ${CFG:+CLAUDE_CONFIG_DIR=$(q "${CFG/#\~/$HOME}") }${DM_CLAUDE_BIN:-claude}"
for a in "$@"; do CMD="$CMD $(q "$a")"; done
$TM new-window -t "$SESSION" -n "$W" -c "$PWD"
$TM send-keys -t "$SESSION:$W" "$CMD" Enter
bash "$(dirname "$0")/bridge-link.sh" >/dev/null 2>&1 || true
echo "$W"
