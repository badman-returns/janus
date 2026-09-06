#!/usr/bin/env bash
# /api/front reads every registered machine's gates, ledger and replies and tells the seat; a reply
# posted through /api/front/reply lands in the right machine and removes its gate; a note lands in
# another; a proof video is served with Range so a <video> can scrub it; a path escape is refused.
# /front serves the one screen. The fleet machine itself is registered under a key that differs from
# its directory name (as it is live: the brain repo is "fleet"), so `fleet` must come from
# config.json's project — the page matches machines against it, and the Talk box posts notes to it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SRV="$HERE/../../plugin-mc/mission-control/server.js"
T=$(mktemp -d); PID=""; trap 'kill $PID 2>/dev/null; rm -rf "$T"' EXIT; fail(){ echo "FAIL test_front_api: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/a/.delivery/inbox" "$T/b/.delivery/inbox" "$T/b/.delivery/replies" "$T/b/proof/x" "$T/brain/.delivery" "$T/brain/proof/y"
echo '{"project":"a","services":{},"claude_config_dir":"~/.claude-tsg"}' > "$T/a/.delivery/config.json"
echo '{"project":"b","services":{},"claude_config_dir":"~/.claude-alt"}' > "$T/b/.delivery/config.json"
echo '{"project":"fleet","services":{}}' > "$T/brain/.delivery/config.json"
printf 'GATE 2 — review proof for x\n\nAPPROVE / REJECT with note\n' > "$T/b/.delivery/inbox/gate-x-proof.txt"
echo '{"ts":"2026-01-01T00:00:00Z","agent":"dm-builder","slice":"x","status":"built","note":"n"}' > "$T/b/.delivery/runs.jsonl"
printf 'via: b\n\nAll quiet.\n' > "$T/b/.delivery/replies/note-1-voice-status.md"
head -c 5000 /dev/zero > "$T/b/proof/x/proof.mp4"
head -c 5000 /dev/zero > "$T/brain/proof/y/a.mp4"
cat > "$T/home/.delivery-machine/registry.json" <<EOF
{"a":{"dir":"$T/a","session":"dm-a","port":1,"ttyd_port":2,"started":"x"},"b":{"dir":"$T/b","session":"dm-b","port":3,"ttyd_port":4,"started":"x"},"fleet":{"dir":"$T/brain","session":"dm-fleettest","port":5,"ttyd_port":6,"started":"x"}}
EOF
PORT=$((20000 + RANDOM % 20000))
HOME="$T/home" node "$SRV" --port "$PORT" --project "$T/brain" >/dev/null 2>&1 & PID=$!; disown
for i in $(seq 1 40); do curl -s "http://127.0.0.1:$PORT/api/front" >/dev/null 2>&1 && break; sleep 0.25; done
J=$(curl -s "http://127.0.0.1:$PORT/api/front")
echo "$J" | python3 -c "
import json,sys; d=json.load(sys.stdin); m={x['project']:x for x in d['machines']}
assert m['b']['seat']=='office' and m['a']['seat']=='personal', 'seat'
assert m['b']['items'][0]['name']=='gate-x-proof.txt' and 'APPROVE' in m['b']['items'][0]['body'], 'gate'
assert m['b']['last']['slice']=='x' and m['b']['video']=='x/proof.mp4', 'ledger or video'
assert m['b']['replies'][0]['body'].startswith('via: b'), 'reply'
assert m['b']['state']=='waiting' and m['a']['state']=='stopped', 'state'
assert d['fleet']=='fleet', 'fleet named by its directory, not its registry key: %r' % d['fleet']
assert any(x['project']==d['fleet'] for x in d['machines']), 'no machine is the fleet: %r' % list(m)
" || fail "front json wrong: $J"
curl -s -X POST -d '{"project":"b","re":"gate-x-proof.txt","text":"APPROVE"}' "http://127.0.0.1:$PORT/api/front/reply" | grep -q '"ok":true' || fail "reply not accepted"
ls "$T/b/.delivery/inbox" | grep -q '^reply-.*gate-x-proof' || fail "reply file not written in machine b"
[ ! -e "$T/b/.delivery/inbox/gate-x-proof.txt" ] || fail "gate not removed"
grep -q 'APPROVE' "$T/b/.delivery/threads/gate-x-proof.md" || fail "thread not appended"
curl -s -X POST -d '{"project":"a","text":"hello a"}' "http://127.0.0.1:$PORT/api/front/note" | grep -q '"ok":true' || fail "note not accepted"
ls "$T/a/.delivery/inbox" | grep -q '^note-' || fail "note not written in machine a"
# the Talk box's offline fallback: a note addressed to the fleet by the name /api/front gave it
F=$(echo "$J" | python3 -c 'import json,sys; print(json.load(sys.stdin)["fleet"])')
curl -s -o /dev/null -w '%{http_code}' -X POST -d "{\"project\":\"$F\",\"text\":\"what is going on\"}" "http://127.0.0.1:$PORT/api/front/note" | grep -q 200 || fail "a note to the fleet ($F) was refused"
ls "$T/brain/.delivery/inbox" | grep -q '^note-' || fail "note not written in the fleet machine"
H=$(curl -s -D - -o /dev/null -H 'Range: bytes=0-9' "http://127.0.0.1:$PORT/api/front/proof?project=b&file=x/proof.mp4")
echo "$H" | grep -q '^HTTP/1.1 206' || fail "no 206 for a range: $H"
echo "$H" | grep -qi 'content-length: 10' || fail "range length wrong"
curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/front/proof?project=b&file=../.delivery/config.json" | grep -q 404 || fail "path escape not refused"
curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/front" | grep -q 200 || fail "/front not served"
# the server's own /proof/ route learns the same Range, and refuses an unsatisfiable one with 416
V=$(curl -s -D - -o /dev/null -H 'Range: bytes=0-9' "http://127.0.0.1:$PORT/proof/y/a.mp4")
echo "$V" | grep -q '^HTTP/1.1 206' || fail "no 206 for a range on /proof/: $V"
echo "$V" | grep -qi 'content-length: 10' || fail "range length wrong on /proof/"
curl -s -o /dev/null -w '%{http_code}' -H 'Range: bytes=999999-' "http://127.0.0.1:$PORT/proof/y/a.mp4" | grep -q 416 || fail "a range past the end must be 416"
[ "$(curl -s --path-as-is -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/proof/../.delivery/config.json")" != 200 ] || fail "/proof/ traversal served the config"
echo "PASS test_front_api"
