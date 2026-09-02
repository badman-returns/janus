#!/usr/bin/env bash
# activity.sh stop: a session outside a dm-* tmux is told about waiting inbox items, once per 120 s.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/activity.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.delivery/inbox"; echo hi > "$T/.delivery/inbox/note-1-hi.txt"
cd "$T"; fail(){ echo "FAIL test_stop_drain: $1"; exit 1; }
WANT='{"decision":"block","reason":"1 inbox item(s) waiting — run /dm process the pending items in .delivery/inbox, then continue"}'
run(){ echo "$1" | env -u TMUX -u DM_TMUX_SESSION "${@:2}" bash "$S" stop; }

out=$(run '{"session_id":"abc12345"}')
[ "$out" = "$WANT" ] || fail "no block outside tmux: '$out'"
[ -f .delivery/.nudge-abc12345 ] || fail "nudge marker not written"
[ -f .delivery/agents/abc12345.json ] || fail "heartbeat not written alongside"
out=$(run '{"session_id":"abc12345"}'); [ -z "$out" ] || fail "second call within 120 s nudged again: $out"
rm .delivery/.nudge-abc12345
out=$(run '{"session_id":"abc12345","stop_hook_active":true}'); [ -z "$out" ] || fail "nudged while stop_hook_active: $out"
out=$(run '{"session_id":"abc12345"}' TMUX=x DM_TMUX_SESSION=dm-foo); [ -z "$out" ] || fail "nudged inside dm-foo: $out"
[ ! -e .delivery/.nudge-abc12345 ] || fail "marker touched on a skipped nudge"
out=$(run '{"session_id":"abc12345"}' TMUX=x DM_TMUX_SESSION=other); [ "$out" = "$WANT" ] || fail "no block in a non-dm tmux: '$out'"
rm .delivery/.nudge-abc12345
out=$(echo '{"session_id":"abc12345"}' | env -u TMUX bash "$S" prompt); [ -z "$out" ] || fail "prompt event printed: $out"
rm .delivery/inbox/note-1-hi.txt
out=$(run '{"session_id":"abc12345"}'); [ -z "$out" ] || fail "nudged with an empty inbox: $out"
cd /; out=$(echo '{}' | env -u TMUX bash "$S" stop); [ -z "$out" ] || fail "not silent outside a dm project: $out"
echo "PASS test_stop_drain"
