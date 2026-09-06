#!/usr/bin/env bash
# Is a service window actually running something? A window that exists but sits at its shell prompt —
# its service Ctrl-C'd by `dm-stop.sh --pause`, or crashed — has a pane shell with no child process.
# orchestrator.sh asks before deciding a service is up; a window at a prompt gets its command again.
# Usage: service-alive.sh <session> <window>   → exit 0 running, 1 at a prompt, 2 no such window
# Env: TMUX_SOCK="-L name" for an isolated tmux server (tests)
set -uo pipefail
TM="tmux ${TMUX_SOCK:-}"
PID=$($TM display -p -t "$1:$2" '#{pane_pid}' 2>/dev/null) || exit 2
[ -n "$PID" ] || exit 2
pgrep -P "$PID" >/dev/null
