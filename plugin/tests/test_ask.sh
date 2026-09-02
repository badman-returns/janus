#!/usr/bin/env bash
# ask.sh: writes an ask card, waits for the dashboard reply, returns it as a deny-with-answer; times out cleanly.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/ask.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.delivery/inbox"; echo '{"project":"asktest","services":{}}' > "$T/.delivery/config.json"
cd "$T"; fail(){ echo "FAIL test_ask: $1"; exit 1; }
# no cockpit is listening for this fake project → ask.sh must fall straight through (no card, no wait)
out=$(echo '{"tool_input":{"questions":[{"question":"q","options":[{"label":"a"}]}]}}' | bash "$S" ask); [ -z "$out" ] || fail "should pass through without a dashboard: $out"
ls .delivery/inbox | grep -q '^ask-' && fail "card written with no dashboard listening"
export DM_ASK_FORCE=1   # the rest of the test simulates the dashboard by hand
IN='{"session_id":"s1","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Own slice or fold in?","header":"Scope","options":[{"label":"Own slice","description":""},{"label":"Fold in","description":""}],"multiSelect":false}]}}'
# answer from "the dashboard" after 1s
( sleep 1; f=$(ls .delivery/inbox | grep '^ask-'); printf 'RE: %s\nOwn slice' "$f" > ".delivery/inbox/reply-1-$f"; rm ".delivery/inbox/$f" ) &
out=$(echo "$IN" | DM_ASK_POLL=0.2 bash "$S" ask)
echo "$out" | grep -q '"permissionDecision": "deny"' || fail "no deny decision: $out"
echo "$out" | grep -q 'Own slice' || fail "answer not returned: $out"
ls .delivery/inbox | grep -q '^reply-' && fail "reply not consumed"
# permission path: the server's real naming (slug of the ask name, 40 chars), reply ALLOW
PIN='{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'
( sleep 1; f=$(ls .delivery/inbox | grep '^ask-'); s=$(echo "$f" | tr -c 'a-z0-9-\n' '-' | cut -c1-40); printf 'RE: %s\nALLOW' "$f" > ".delivery/inbox/reply-2-$s.txt"; rm ".delivery/inbox/$f" ) &
out=$(echo "$PIN" | DM_ASK_POLL=0.2 bash "$S" permission)
echo "$out" | grep -q '"hookEventName": "PermissionRequest"' || fail "no permission output: $out"
echo "$out" | grep -q '"behavior": "allow"' || fail "ALLOW not honoured: $out"
# timeout path: no reply → no output, exit 0, card removed
out=$(echo "$IN" | DM_ASK_TIMEOUT=1 DM_ASK_POLL=0.2 bash "$S" ask); rc=$?
[ $rc -eq 0 ] || fail "timeout exit $rc"
[ -z "$out" ] || fail "timeout produced output: $out"
ls .delivery/inbox | grep -q '^ask-' && fail "stale ask card left behind"
echo "PASS test_ask"
