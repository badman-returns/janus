#!/usr/bin/env bash
# dm-attach.sh: creates a grouped view session on the target window; missing window → message + exit 1.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/dm-attach.sh"
T=$(mktemp -d); trap 'rm -rf "$T"; tmux kill-session -t attach-driver 2>/dev/null; tmux kill-session -t dm-attachtest 2>/dev/null' EXIT
mkdir -p "$T/.delivery"; echo '{"project":"attachtest","services":{}}' > "$T/.delivery/config.json"
cd "$T"; fail(){ echo "FAIL test_attach: $1"; exit 1; }
tmux new-session -d -s dm-attachtest -n api 'sleep 60'
tmux new-window -d -t dm-attachtest -n worker 'sleep 60'
out=$(bash "$S" nope 2>&1); [ $? -eq 1 ] || fail "missing window did not exit 1"
echo "$out" | grep -q "no window" || fail "missing window message absent: $out"
# drive the attach inside a detached tmux client so it does not need a tty here
tmux new-session -d -s attach-driver -c "$T" "bash '$S' worker; sleep 5"
sleep 1
tmux ls | grep -q '^view-' || fail "no view-* grouped session created"
v=$(tmux ls -F '#S' | grep '^view-' | head -1)
[ "$(tmux display-message -p -t "$v" '#W')" = "worker" ] || fail "view session not on window worker"
[ "$(tmux display-message -p -t dm-attachtest '#W')" = "api" ] || fail "source session current window was moved"
tmux kill-session -t attach-driver
sleep 1
tmux ls 2>/dev/null | grep -q '^view-' && fail "view session survived detach"
echo "PASS test_attach"
