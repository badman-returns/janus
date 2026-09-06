#!/usr/bin/env bash
# The id of a machine's live Claude window — the first `claude*` window of its tmux session. Windows are
# named `claude@<project>` (and `claude-2@<project>`), and tmux prefix-matches names, so `-t dm-x:claude`
# is ambiguous the moment a second session opens; an id never is. Prints nothing and exits 1 with none.
# Usage: session-window.sh <project>        → @12
set -uo pipefail
W=$(tmux list-windows -t "dm-${1:?project}" -F '#{window_id} #W' 2>/dev/null | awk '$2 ~ /^claude/ {print $1; exit}')
[ -n "$W" ] && echo "$W"
