#!/usr/bin/env bash
# Type one line into a Claude window and press Enter — only when its input box is empty. A line left
# unsent in the box (the phone's text that arrived without its Enter, an operator's half-typed thought)
# would be submitted together with ours: "push it" + a pickup line pushes. So the box is read first;
# a draft means nothing is typed, exit 3, and the draft is named so someone clears it or sends it.
# Usage: type-line.sh <tmux window (an id such as @12, never a name two windows can share)> <line>
# Env: TMUX_SOCK="-L name" for an isolated tmux server (tests).
# Exit: 0 typed · 2 no input line visible (a dialog, a menu, a dead window) · 3 the box holds a draft
set -uo pipefail
TM="tmux ${TMUX_SOCK:-}"
WIN=${1:?window}; LINE=${2:?line}
PANE=$($TM capture-pane -p -t "$WIN" 2>/dev/null) || { echo "type-line: no window $WIN" >&2; exit 2; }
PROMPT=$(printf '%s\n' "$PANE" | grep -E '^[[:space:]]*(❯|>) ?' | tail -1)
[ -n "$PROMPT" ] || { echo "type-line: no input line visible in $WIN, nothing typed" >&2; exit 2; }
DRAFT=$(printf '%s' "$PROMPT" | sed -E 's/^[[:space:]]*(❯|>) ?//; s/[[:space:]]+$//')
case "$DRAFT" in
  ""|Try\ \"*) ;;                                   # empty, or Claude Code's own placeholder hint
  *) echo "type-line: $WIN holds an unsent line: \"$DRAFT\" — nothing typed; clear it or send it there" >&2; exit 3 ;;
esac
$TM send-keys -t "$WIN" -l "$LINE" && sleep 1 && $TM send-keys -t "$WIN" Enter
