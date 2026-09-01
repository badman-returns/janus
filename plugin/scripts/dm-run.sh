#!/usr/bin/env bash
# Run a command in a named tmux window of this project's machine — THE way
# agents start anything that serves. Usage: dm-run.sh <window-name> <command...>
set -euo pipefail
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])")
SESSION="dm-$PROJ"; NAME="$1"; shift
tmux has-session -t "$SESSION" 2>/dev/null || { echo "machine not running — run orchestrator.sh first"; exit 1; }
if tmux list-windows -t "$SESSION" -F '#W' | grep -qx "$NAME"; then
  tmux send-keys -t "$SESSION:$NAME" C-c "" 2>/dev/null || true
else
  tmux new-window -t "$SESSION" -n "$NAME" -c "$PWD"
fi
tmux send-keys -t "$SESSION:$NAME" "$*" Enter
echo "running in tmux $SESSION:$NAME — logs: tmux capture-pane -p -t $SESSION:$NAME"
