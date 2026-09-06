#!/usr/bin/env bash
# The Talk column is files, not the voice loop. A typed line reaches the concierge as a note AND
# leaves a line in the fleet's talk.jsonl — the note is deleted when it is answered, so the journal
# is the only record of what was asked. /api/front joins that journal to replies/<stem>.md: no file
# yet means the exchange is still open (reply: null); once written, its header block is parsed the
# way voice/speech.py does, with refs: as a list of paths. The journal is the fleet's alone.
# Also: the vendored marked is served (a 404 there flattens every reply), and /api/front/open
# refuses a refs: path that climbs out of the machine.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SRV="$HERE/../../plugin-mc/mission-control/server.js"
T=$(mktemp -d); PID=""; trap 'kill $PID 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_front_talk: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/brain/.delivery/inbox" "$T/b/.delivery/inbox"
echo '{"project":"fleet","services":{}}' > "$T/brain/.delivery/config.json"
echo '{"project":"b","services":{}}' > "$T/b/.delivery/config.json"
cat > "$T/home/.delivery-machine/registry.json" <<EOF
{"fleet":{"dir":"$T/brain","session":"dm-fleettalk","port":5,"ttyd_port":6,"started":"x"},"b":{"dir":"$T/b","session":"dm-b","port":3,"ttyd_port":4,"started":"x"}}
EOF
PORT=$((20000 + RANDOM % 20000))
HOME="$T/home" node "$SRV" --port "$PORT" --project "$T/brain" >/dev/null 2>&1 & PID=$!; disown
for i in $(seq 1 40); do curl -s "http://127.0.0.1:$PORT/api/front" >/dev/null 2>&1 && break; sleep 0.25; done

N=$(curl -s -X POST -d '{"project":"fleet","text":"what is going on"}' "http://127.0.0.1:$PORT/api/front/note")
echo "$N" | grep -q '"ok":true' || fail "note refused: $N"
NAME=$(echo "$N" | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
STEM="${NAME%.txt}"
[ "$(wc -l < "$T/brain/.delivery/talk.jsonl")" -eq 1 ] || fail "one note must leave one journal line"
python3 - "$T/brain/.delivery/talk.jsonl" "$STEM" <<'EOF' || fail "journal line wrong"
import json,sys
r = json.loads(open(sys.argv[1]).read().strip())
assert r["stem"] == sys.argv[2], (r, sys.argv[2])
assert r["text"] == "what is going on" and r["source"] == "typed" and r["ts"], r
EOF
# a note to another machine is that machine's business: the fleet's thread does not grow
curl -s -X POST -d '{"project":"b","text":"not for the thread"}' "http://127.0.0.1:$PORT/api/front/note" | grep -q '"ok":true' || fail "note to b refused"
[ "$(wc -l < "$T/brain/.delivery/talk.jsonl")" -eq 1 ] || fail "another machine's note landed in the fleet journal"
[ ! -e "$T/b/.delivery/talk.jsonl" ] || fail "talk.jsonl written outside the fleet"

curl -s "http://127.0.0.1:$PORT/api/front" | python3 -c "
import json,sys; t=json.load(sys.stdin)['talk']
assert len(t)==1, t
assert t[0]['text']=='what is going on' and t[0]['stem']=='$STEM', t
assert t[0]['reply'] is None, 'an unanswered exchange must say so: %r' % t[0]['reply']
" || fail "unanswered exchange wrong"

mkdir -p "$T/brain/.delivery/replies"
printf 'via: b\nrefs: docs/a.md ../b/notes.md\nspeak: no\n\n## Two things\n\n- one\n- two\n' > "$T/brain/.delivery/replies/$STEM.md"
curl -s "http://127.0.0.1:$PORT/api/front" | python3 -c "
import json,sys; r=json.load(sys.stdin)['talk'][0]['reply']
assert r, 'reply not picked up'
assert r['headers']['via']=='b' and r['headers']['speak']=='no', r['headers']
assert r['headers']['refs']==['docs/a.md','../b/notes.md'], 'refs must be a list: %r' % r['headers'].get('refs')
assert r['body'].startswith('## Two things'), 'header block not stripped: %r' % r['body'][:40]
assert r['mtime'], 'no mtime'
" || fail "answered exchange wrong"

# the reply's markdown needs its renderer: vendored, pinned, served as JS
H=$(curl -s -D - -o "$T/marked.js" "http://127.0.0.1:$PORT/vendor/marked.min.js")
echo "$H" | grep -q '^HTTP/1.1 200' || fail "marked not served: $H"
echo "$H" | grep -qi 'content-type: text/javascript' || fail "marked served with the wrong type"
grep -q 'marked' "$T/marked.js" || fail "marked body empty"
curl -s "http://127.0.0.1:$PORT/front" | grep -q '/vendor/marked.min.js' || fail "/front does not load marked"

# a refs: chip opens a file — never one outside the machine it names
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{"project":"b","file":"../brain/.delivery/config.json"}' "http://127.0.0.1:$PORT/api/front/open")" = "400" ] || fail "a path outside the machine was opened"

node --check "$HERE/../../plugin-mc/mission-control/js/front.js" || fail "front.js does not parse"
echo "PASS test_front_talk"
