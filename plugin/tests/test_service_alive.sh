#!/usr/bin/env bash
# service-alive.sh: 0 when the window's shell has a child (the service runs), 1 at a bare prompt, 2 when
# the window is missing — so orchestrator.sh can restart a service that --pause stopped in place.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SA="$HERE/../scripts/service-alive.sh"
export TMUX_SOCK="-L sa-$$"; trap 'tmux $TMUX_SOCK kill-server 2>/dev/null' EXIT
fail(){ echo "FAIL test_service_alive: $1"; exit 1; }
tmux $TMUX_SOCK new-session -d -s dm-sa -n control
tmux $TMUX_SOCK new-window -d -t dm-sa -n svc          # a bare shell: what a paused service looks like
tmux $TMUX_SOCK new-window -d -t dm-sa -n run 'sleep 300'   # a window whose pane is the command itself
tmux $TMUX_SOCK new-window -d -t dm-sa -n typed; tmux $TMUX_SOCK send-keys -t dm-sa:typed 'sleep 300' Enter   # started the way orchestrator.sh starts a service
sleep 0.7
bash "$SA" dm-sa run; [ $? = 0 ] || fail "a running service reported not alive"
for i in $(seq 1 24); do bash "$SA" dm-sa typed && break; sleep 0.25; done   # the shell needs its startup before it runs the line
bash "$SA" dm-sa typed; [ $? = 0 ] || fail "a service typed into a shell reported not alive"
bash "$SA" dm-sa svc; [ $? = 1 ] || fail "a bare prompt reported alive"
bash "$SA" dm-sa nope; [ $? = 2 ] || fail "a missing window did not exit 2"
tmux $TMUX_SOCK send-keys -t dm-sa:svc 'sleep 300' Enter; sleep 0.7
bash "$SA" dm-sa svc; [ $? = 0 ] || fail "a restarted service reported not alive"
echo "PASS test_service_alive"
