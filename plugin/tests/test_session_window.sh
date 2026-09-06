#!/usr/bin/env bash
# session-window.sh prints the id of the first claude* window of dm-<project>, and nothing for none.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SW="$HERE/../scripts/session-window.sh"
S="dm-swtest-$$"; trap 'tmux kill-session -t "$S" 2>/dev/null' EXIT; fail(){ echo "FAIL test_session_window: $1"; exit 1; }
tmux new-session -d -s "$S" -n control; tmux new-window -d -t "$S" -n "claude@swtest-$$"; tmux new-window -d -t "$S" -n "claude-2@swtest-$$"
ID=$(bash "$SW" "swtest-$$") || fail "no id printed"
[ "$(tmux display -p -t "$ID" '#W')" = "claude@swtest-$$" ] || fail "wrong window: $(tmux display -p -t "$ID" '#W')"
bash "$SW" "nosuch-$$" >/dev/null 2>&1 && fail "printed an id for a machine that is not running"
echo "PASS test_session_window"
