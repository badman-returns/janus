#!/usr/bin/env bash
# Link every machine's claude* window into one tmux session, `bridge`, so a single ccgram
# instance can bind each to a Telegram topic. A linked window is the SAME window: keys typed from
# the phone land in the machine's own session; Janus's window-name contract in dm-<project> is
# untouched. Idempotent; safe to run after every orchestrator.sh and dm-session.sh.
# Usage: bridge-link.sh        (TMUX_SOCK="-L name" for an isolated tmux server, tests only)
set -uo pipefail
TM="tmux ${TMUX_SOCK:-}"
REG="$HOME/.delivery-machine/registry.json"
[ -s "$REG" ] || exit 0
$TM has-session -t bridge 2>/dev/null || $TM new-session -d -s bridge -n __main__ 'sleep 2147483647'
linked=$($TM list-windows -t bridge -F '#{window_id}' 2>/dev/null)
python3 -c "import json;[print(v['session']) for v in json.load(open('$REG')).values()]" | while read -r S; do
  $TM has-session -t "$S" 2>/dev/null || continue
  # `< <(…)` and not a pipe: the loop must run in this shell so appending to `linked` sticks.
  # The same window can be listed twice (one window, two indices), and it must link only once.
  while read -r WID WNAME; do
    case "$WNAME" in claude*) ;; *) continue ;; esac
    echo "$linked" | grep -qx "$WID" && continue
    $TM link-window -d -s "$S:$WID" -t "bridge:" && echo "linked $S:$WNAME ($WID)"
    linked="$linked"$'\n'"$WID"
  done < <($TM list-windows -t "$S" -F '#{window_id} #{window_name}')
done
# a window killed in its machine is gone from bridge too (same window), nothing to prune;
# a __main__ placeholder is kept so ccgram never sees an empty session.
exit 0
