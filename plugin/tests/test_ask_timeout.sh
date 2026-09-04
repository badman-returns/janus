#!/usr/bin/env bash
# ask.sh holds the terminal while it waits for a dashboard answer, and the TUI prompt cannot
# appear until it returns — so the wait length is a UX decision, not a constant. 580s suits an
# operator on a phone; at the keyboard it reads as a hang. Default short, long wait opt-in per
# project via config `ask_timeout`.
#
# The first case is behavioural (it measures the actual wait). The second pins the fallback
# constant by reading the script, which is weaker — but a 45s test is not worth the wall clock.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; A="$HERE/../scripts/ask.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL test_ask_timeout: $1"; exit 1; }

cd "$T" || fail "cd"
mkdir -p .delivery/inbox
echo '{"project":"t","ask_timeout":1}' > .delivery/config.json

# DM_ASK_FORCE skips the "is a cockpit listening" early exit, so we reach the wait loop.
IN='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"go?","options":[{"label":"yes"}]}]}}'
start=$(date +%s)
echo "$IN" | DM_ASK_FORCE=1 DM_ASK_POLL=1 bash "$A" ask >/dev/null 2>&1
took=$(( $(date +%s) - start ))
[ "$took" -le 6 ] || fail "config ask_timeout=1 was ignored; waited ${took}s"

# the card must not be left behind for an operator to answer when nobody is waiting any more
ls .delivery/inbox/ask-*.txt >/dev/null 2>&1 && fail "timed-out card left in the inbox"

# an env override still wins (the test seam every other script here uses)
echo '{"project":"t","ask_timeout":600}' > .delivery/config.json
start=$(date +%s)
echo "$IN" | DM_ASK_FORCE=1 DM_ASK_TIMEOUT=1 DM_ASK_POLL=1 bash "$A" ask >/dev/null 2>&1
took=$(( $(date +%s) - start ))
[ "$took" -le 6 ] || fail "DM_ASK_TIMEOUT did not override config; waited ${took}s"

# fallback when neither is set: short enough for someone at the keyboard
# code lines only: the script's own comment explains why 580 was wrong, and a bare grep hits it
CODE=$(grep -v '^[[:space:]]*#' "$A")
echo "$CODE" | grep -q ':-45}' || fail "default wait is not 45s — a long default is the hang this fixes"
echo "$CODE" | grep -q '580'   && fail "the old 580s default is still in the resolution path"

echo "PASS test_ask_timeout"
