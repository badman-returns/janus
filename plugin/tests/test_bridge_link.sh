#!/usr/bin/env bash
# bridge-link.sh links every claude* window (now claude@<project>, claude-2@<project>) of every registered machine into session `bridge`, once.
set -u
unset DM_BRIDGE   # this test is the linker itself, on its own tmux server; a suite-wide DM_BRIDGE=0 must not switch it off
HERE="$(cd "$(dirname "$0")" && pwd)"; BL="$HERE/../scripts/bridge-link.sh"
T=$(mktemp -d); export TMUX_SOCK="-L bl-$$"; trap 'tmux $TMUX_SOCK kill-server 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_bridge_link: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/p1" "$T/p2"
cat > "$T/home/.delivery-machine/registry.json" <<EOF
{"p1":{"dir":"$T/p1","session":"dm-p1","port":1,"ttyd_port":2,"started":"x"},
 "p2":{"dir":"$T/p2","session":"dm-p2","port":3,"ttyd_port":4,"started":"x"},
 "dead":{"dir":"$T/p1","session":"dm-dead","port":5,"ttyd_port":6,"started":"x"}}
EOF
tmux $TMUX_SOCK new-session -d -s dm-p1 -n control 'sleep 300'
tmux $TMUX_SOCK new-window -d -t dm-p1 -n claude@p1 'sleep 300'
tmux $TMUX_SOCK new-window -d -t dm-p1 -n claude-2@p1 'sleep 300'
tmux $TMUX_SOCK new-session -d -s dm-p2 -n claude@p2 'sleep 300'
HOME="$T/home" bash "$BL" || fail "bridge-link exited $?"
tmux $TMUX_SOCK has-session -t bridge || fail "no bridge session"
N=$(tmux $TMUX_SOCK list-windows -t bridge -F '#{window_id}' | sort -u | wc -l | tr -d ' ')
[ "$N" = 4 ] || fail "expected 4 windows in bridge (3 linked + __main__), got $N: $(tmux $TMUX_SOCK list-windows -t bridge -F '#W')"
W1=$(tmux $TMUX_SOCK list-windows -t dm-p1 -F '#{window_id} #W' | awk '$2=="claude@p1"{print $1}')
tmux $TMUX_SOCK list-windows -t bridge -F '#{window_id}' | grep -qx "$W1" || fail "dm-p1:claude@p1 not linked"
HOME="$T/home" bash "$BL" || fail "second run failed"
N2=$(tmux $TMUX_SOCK list-windows -t bridge -F '#{window_id}' | sort -u | wc -l | tr -d ' ')
[ "$N2" = 4 ] || fail "not idempotent: $N2 windows after second run"
tmux $TMUX_SOCK kill-window -t 'dm-p1:claude-2@p1'
HOME="$T/home" bash "$BL" || fail "third run failed"
tmux $TMUX_SOCK list-windows -t bridge -F '#W' | grep -qx 'claude-2@p1' && fail "dead window still listed in bridge"

# one window at two indices (the state a live machine can be in) still links exactly once.
# bridge is rebuilt first so the duplicate is linked fresh — otherwise the previous run's
# window ids are already in `bridge` and nothing is being tested.
tmux $TMUX_SOCK link-window -d -s "dm-p1:$W1" -t 'dm-p1:'
tmux $TMUX_SOCK kill-session -t bridge
HOME="$T/home" bash "$BL" || fail "fourth run failed"
D=$(tmux $TMUX_SOCK list-windows -t bridge -F '#{window_id}' | grep -cx "$W1" | tr -d ' ')
[ "$D" = 1 ] || fail "window at two indices linked $D times into bridge, expected 1"

# stop must mean stop: dm-stop.sh kills each window by id before the session, because a window
# linked into bridge outlives kill-session on its own machine.
W2=$(tmux $TMUX_SOCK list-windows -t dm-p2 -F '#{window_id}' | head -1)
PID=$(tmux $TMUX_SOCK list-panes -s -t dm-p2 -F '#{pane_pid}' | head -1)
for w in $(tmux $TMUX_SOCK list-windows -t dm-p2 -F '#{window_id}'); do tmux $TMUX_SOCK kill-window -t "$w" 2>/dev/null; done
tmux $TMUX_SOCK list-windows -t bridge -F '#{window_id}' | grep -qx "$W2" && fail "dm-p2 claude ($W2) survived in bridge after a dm-stop-style window kill"
for i in 1 2 3 4 5 6 7 8 9 10; do ps -p "$PID" >/dev/null 2>&1 || break; sleep 0.3; done
ps -p "$PID" >/dev/null 2>&1 && fail "dm-p2 claude pane process $PID survived the window kill"
echo "PASS test_bridge_link"
