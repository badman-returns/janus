#!/usr/bin/env bash
# service-alive.sh: 0 when the window's shell has a child (the service runs), 1 at a bare prompt, 2 when
# the window is missing — so orchestrator.sh can restart a service that --pause stopped in place.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SA="$HERE/../scripts/service-alive.sh"
export TMUX_SOCK="-L sa-$$"; trap 'tmux $TMUX_SOCK kill-server 2>/dev/null' EXIT
fail(){ echo "FAIL test_service_alive: $1"; exit 1; }
tmux $TMUX_SOCK new-session -d -s dm-sa -n control
tmux $TMUX_SOCK new-window -d -t dm-sa -n svc          # a bare shell: what a paused service looks like
tmux $TMUX_SOCK new-window -d -t dm-sa -n run 'sleep 300'
sleep 0.7
bash "$SA" dm-sa run; [ $? = 0 ] || fail "a running service reported not alive"
bash "$SA" dm-sa svc; [ $? = 1 ] || fail "a bare prompt reported alive"
bash "$SA" dm-sa nope; [ $? = 2 ] || fail "a missing window did not exit 2"
tmux $TMUX_SOCK send-keys -t dm-sa:svc 'sleep 300' Enter; sleep 0.7
bash "$SA" dm-sa svc; [ $? = 0 ] || fail "a restarted service reported not alive"
echo "PASS test_service_alive"
