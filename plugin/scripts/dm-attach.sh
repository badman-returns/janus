#!/usr/bin/env bash
# ttyd target: attach THIS client to one window of the machine through its own
# grouped session, so two browser tiles (or the operator's own attach) never
# fight over the current window. Panes are shared; only the view is private.
# The view session destroys itself on detach. Usage: dm-attach.sh <window>
set -uo pipefail
W="${1:-}"
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])" 2>/dev/null) || { echo "not a dm project"; exit 1; }
SESSION="dm-$PROJ"
tmux list-windows -t "$SESSION" -F '#W' 2>/dev/null | grep -qx "$W" || { echo "no window '$W' in $SESSION"; exit 1; }
V="view-$$-$RANDOM"
unset TMUX   # tmux refuses to nest otherwise; a view is a client, nesting is fine here
exec tmux new-session -t "$SESSION" -s "$V" \; set-option destroy-unattached on \; set-option status off \; select-window -t "$V:$W"
