#!/usr/bin/env bash
# Is a service window actually running something? A window that exists but sits at its shell prompt —
# its service Ctrl-C'd by `dm-stop.sh --pause`, or crashed — has a pane shell with no child process.
# orchestrator.sh asks before deciding a service is up; a window at a prompt gets its command again.
# Usage: service-alive.sh <session> <window>   → exit 0 running, 1 at a prompt, 2 no such window
# Env: TMUX_SOCK="-L name" for an isolated tmux server (tests)
set -uo pipefail
TM="tmux ${TMUX_SOCK:-}"
# list-windows, exact name: `display -p -t session:name` answers for the *current* window when the name
# does not exist, so it can never say "no such window"
OUT=$($TM list-windows -t "$1" -F '#{window_name} #{pane_pid} #{pane_current_command}' 2>/dev/null | awk -v w="$2" '$1==w {print $2, $3; exit}')
[ -n "$OUT" ] || exit 2
PID=${OUT%% *}; CMD=${OUT#* }
# At its prompt, the pane's front process is the shell tmux opens windows with; running anything, it is
# that thing (python3, whisper-server, bash for a script). Counting the shell's children does not work
# here: a zsh prompt on this Mac keeps a child of its own (the prompt theme's daemon).
# ponytail: a bash script started under a bash login shell reads as "at its prompt"; every machine here
# opens zsh, and no service is a zsh script. Compare against tmux's default-shell if that changes.
SH=$(basename "$($TM show -gv default-shell 2>/dev/null || echo "${SHELL:-/bin/sh}")")
case "${CMD#-}" in "$SH") exit 1 ;; *) exit 0 ;; esac
