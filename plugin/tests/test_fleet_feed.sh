#!/usr/bin/env bash
# fleet-feed.py: a ledger line becomes one short message; a gate file becomes a card once; an outbox
# file is sent by type and moved to sent/. Telegram is a local stub that records every request.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; FF="$HERE/../scripts/fleet-feed.py"
T=$(mktemp -d); trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_fleet_feed: $1"; exit 1; }
cat > "$T/stub.py" <<'EOF'
import http.server, json, sys, re, urllib.parse
LOG = sys.argv[2]; FAILS = LOG + '.fail'   # write "N [code]" there: the next N requests answer code (500)
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(n)
        try: left, code = (open(FAILS).read().split() + ['500'])[:2]
        except Exception: left, code = '0', '500'
        if int(left) > 0:                     # a refused send: not logged, so it never counts as sent
            open(FAILS, 'w').write(f'{int(left) - 1} {code}')
            self.send_response(int(code)); self.end_headers(); self.wfile.write(b'{"ok":false}'); return
        method = self.path.rsplit('/', 1)[-1]
        ctype = self.headers.get('Content-Type', '')
        text = ''
        if 'multipart' in ctype:
            m = re.search(rb'name="(caption|text)"\r\n\r\n(.*?)\r\n--', body, re.S); text = m.group(2).decode() if m else ''
            fname = re.search(rb'filename="([^"]+)"', body); text += ' FILE=' + (fname.group(1).decode() if fname else '')
        else:
            text = urllib.parse.unquote_plus(body.decode())   # form body -> readable text
        open(LOG, 'a').write(json.dumps({'method': method, 'text': text}, ensure_ascii=False) + '\n')
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers()
        self.wfile.write(b'{"ok":true,"result":{"message_id":1}}')
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
EOF
PORT=$((20000 + RANDOM % 20000)); python3 "$T/stub.py" $PORT "$T/calls.log" & SRV=$!; sleep 0.5
mkdir -p "$T/home/.delivery-machine" "$T/m1/.delivery/inbox" "$T/m1/.delivery/outbox" "$T/m1/.delivery/agents"
echo "{\"m1\":{\"dir\":\"$T/m1\",\"session\":\"dm-m1\",\"port\":1,\"ttyd_port\":2,\"started\":\"x\"}}" > "$T/home/.delivery-machine/registry.json"
echo '{"ts":"2026-09-05T10:00:00Z","agent":"dm-verifier","slice":"desk","status":"done","note":"PASS — api 887/887. All five claims driven live against branch f851106 and a great deal more text follows here that must be cut to a headline."}' > "$T/m1/.delivery/runs.jsonl"
printf 'GATE 2 — review proof for desk\n\nbranch: feat/desk\nAPPROVE / REJECT with note\n' > "$T/m1/.delivery/inbox/gate-desk-proof.txt"
printf '\x89PNG\r\n\x1a\n' > "$T/m1/.delivery/outbox/1-shot.png"; echo "the shot" > "$T/m1/.delivery/outbox/1-shot.png.caption"
ENV="HOME=$T/home TELEGRAM_BOT_TOKEN=t FEED_CHAT_ID=42 TELEGRAM_API_BASE=http://127.0.0.1:$PORT"
# m1 is a machine the feed has already seen (its cursor is at 0), the way the live five are — a
# ledger the feed has NEVER seen starts at its end instead, which is the m2 case at the bottom
python3 -c "import json,sys;json.dump({'offsets':{sys.argv[1]:0},'announced':[],'silence':{}},open(sys.argv[2],'w'))" \
  "$T/m1/.delivery/runs.jsonl" "$T/home/.delivery-machine/feed-state.json"
env $ENV python3 "$FF" --once || fail "first pass exited $?"
grep -q '"method": "sendMessage"' "$T/calls.log" || fail "no sendMessage"
grep -q 'm1 · desk · dm-verifier done · PASS — api 887/887.' "$T/calls.log" || fail "ledger headline wrong: $(cat "$T/calls.log")"
grep -c 'GATE 2' "$T/calls.log" | grep -qx 1 || fail "gate card not sent exactly once"
# the card says what the concierge answers to, and names its own file so two open cards stay apart
grep -q 'Answer here: approve m1' "$T/calls.log" || fail "gate card is not in the concierge's words: $(cat "$T/calls.log")"
grep -q 'card: gate-desk-proof.txt' "$T/calls.log" || fail "gate card does not name its file"
grep -q '/gate ' "$T/calls.log" && fail "gate card still names the /gate command, which does not exist"
grep -q '"method": "sendPhoto"' "$T/calls.log" || fail "png not sent as photo"
grep -q 'the shot FILE=1-shot.png' "$T/calls.log" || fail "caption or filename missing"
[ -f "$T/m1/.delivery/outbox/sent/1-shot.png" ] || fail "outbox file not moved to sent/"
[ ! -f "$T/m1/.delivery/outbox/1-shot.png.caption" ] || fail "caption sidecar left behind"
env $ENV python3 "$FF" --once || fail "second pass exited $?"
grep -c 'GATE 2' "$T/calls.log" | grep -qx 1 || fail "gate card re-sent on second pass"
grep -c 'dm-verifier done' "$T/calls.log" | grep -qx 1 || fail "ledger line re-sent"
echo '{"ts":"2026-09-05T10:05:00Z","agent":"dm-builder","slice":"badge","status":"dispatched","note":"round 1"}' >> "$T/m1/.delivery/runs.jsonl"
env $ENV python3 "$FF" --once || fail "third pass exited $?"
grep -q 'm1 · badge · dm-builder dispatched · round 1' "$T/calls.log" || fail "appended line not posted"

# (a) a re-gated slice: dm-gate.sh rewrites the same filename, so a later mtime must be a new card
sleep 1
printf 'GATE 2 — review proof for desk\n\nbranch: feat/desk\nround 2, after the rework\n' > "$T/m1/.delivery/inbox/gate-desk-proof.txt"
env $ENV python3 "$FF" --once || fail "re-gate pass exited $?"
grep -c 'GATE 2' "$T/calls.log" | grep -qx 2 || fail "re-gated slice never announced again"
env $ENV python3 "$FF" --once || fail "pass after the re-gate exited $?"
grep -c 'GATE 2' "$T/calls.log" | grep -qx 2 || fail "re-gate card sent twice"
COUNT='import json,sys; print(len(json.load(open(sys.argv[1]))["announced"]))'
python3 -c "$COUNT" "$T/home/.delivery-machine/feed-state.json" | grep -qx 2 || fail "announced is not one entry per card sent for the live file"
rm "$T/m1/.delivery/inbox/gate-desk-proof.txt"          # answered: the entry must not outlive the file
env $ENV python3 "$FF" --once || fail "pass after answering the gate exited $?"
python3 -c "$COUNT" "$T/home/.delivery-machine/feed-state.json" | grep -qx 0 || fail "answered gate left in announced"

# (b) an ask larger than the 1500-char send cap is parsed whole; only the rendered card is capped
python3 - "$T/m1/.delivery/inbox/ask-port.txt" <<'EOF'
import json, sys
json.dump({"title": "Which port for the cockpit?", "context": "background prose " * 100,
           "questions": [{"question": "port", "options": ["5501", "5502"]}]}, open(sys.argv[1], "w"))
EOF
[ "$(wc -c < "$T/m1/.delivery/inbox/ask-port.txt")" -gt 1500 ] || fail "ask fixture is not over the cap"
env $ENV python3 "$FF" --once || fail "ask pass exited $?"
grep -q 'Which port for the cockpit?' "$T/calls.log" || fail "long ask card missing"
grep -q -- '- port: 5501 | 5502' "$T/calls.log" || fail "long ask questions not rendered"
grep -q 'questions' "$T/calls.log" && fail "long ask sent as raw cut JSON"

# (c) a send that fails keeps the cursor on its line, and that line goes out on the next pass
echo '{"ts":"2026-09-05T10:10:00Z","agent":"dm-builder","slice":"badge","status":"working","note":"survives a 500"}' >> "$T/m1/.delivery/runs.jsonl"
echo 3 > "$T/calls.log.fail"                            # one send = three attempts, all refused
ERR=$(env $ENV python3 "$FF" --once 2>&1 >/dev/null) || fail "pass with a failed send exited $?"
echo "$ERR" | grep -q 'telegram failed: sendMessage' || fail "no stderr line for the failed send: $ERR"
grep -q 'survives a 500' "$T/calls.log" && fail "a refused line was recorded as sent"
env $ENV python3 "$FF" --once || fail "retry pass exited $?"
grep -c 'survives a 500' "$T/calls.log" | grep -qx 1 || fail "failed ledger line not retried on the next pass"

# a 400 is permanent: the line is stepped over (no retry) so the machine's later lines still flow
echo '{"ts":"2026-09-05T10:15:00Z","agent":"dm-builder","slice":"badge","status":"working","note":"rejected for good"}' >> "$T/m1/.delivery/runs.jsonl"
echo '{"ts":"2026-09-05T10:16:00Z","agent":"dm-builder","slice":"badge","status":"working","note":"the line behind it"}' >> "$T/m1/.delivery/runs.jsonl"
echo "1 400" > "$T/calls.log.fail"                      # one rejection; a retry would send it after
ERR=$(env $ENV python3 "$FF" --once 2>&1 >/dev/null) || fail "pass with a rejected send exited $?"
echo "$ERR" | grep -qx 'telegram rejected: sendMessage: HTTP 400' || fail "no stderr line for the rejection: $ERR"
grep -q 'rejected for good' "$T/calls.log" && fail "a rejected line was retried and reached the log"
grep -q 'the line behind it' "$T/calls.log" || fail "a rejected line blocked the rest of the ledger"
env $ENV python3 "$FF" --once || fail "pass after the rejection exited $?"
grep -q 'rejected for good' "$T/calls.log" && fail "cursor did not advance past the rejected line"

# a rejected gate card is marked announced, so it is not re-sent on every pass forever
printf 'GATE 2 — review proof for badge\n' > "$T/m1/.delivery/inbox/gate-badge-proof.txt"
echo "1 400" > "$T/calls.log.fail"
env $ENV python3 "$FF" --once 2>/dev/null || fail "pass with a rejected gate card exited $?"
env $ENV python3 "$FF" --once || fail "pass after the rejected gate card exited $?"
grep -c 'review proof for badge' "$T/calls.log" | grep -qx 0 || fail "rejected gate card re-sent"

# a rejected outbox file is parked in sent/ as .rejected, where the operator can see it
printf '\x89PNG\r\n\x1a\n' > "$T/m1/.delivery/outbox/2-bad.png"
echo "1 400" > "$T/calls.log.fail"
env $ENV python3 "$FF" --once 2>/dev/null || fail "pass with a rejected outbox file exited $?"
[ -f "$T/m1/.delivery/outbox/sent/2-bad.png.rejected" ] || fail "rejected outbox file not parked as .rejected"
[ ! -e "$T/m1/.delivery/outbox/2-bad.png" ] || fail "rejected outbox file left to be retried forever"

# a .gitkeep or a still-empty file is not a message: nothing sent, nothing moved
: > "$T/m1/.delivery/outbox/.gitkeep"; : > "$T/m1/.delivery/outbox/note.txt"
N=$(grep -c '' "$T/calls.log")
env $ENV python3 "$FF" --once || fail "pass with an empty outbox file exited $?"
[ "$(grep -c '' "$T/calls.log")" = "$N" ] || fail "a dot or empty outbox file was sent: $(tail -1 "$T/calls.log")"
[ -f "$T/m1/.delivery/outbox/.gitkeep" ] || fail ".gitkeep was moved out of the outbox"
[ -f "$T/m1/.delivery/outbox/note.txt" ] || fail "an empty outbox file was moved"

# a machine registered after the feed started: its ledger is history, not news. First sight posts
# nothing; the first line written after that does go out.
mkdir -p "$T/m2/.delivery/inbox" "$T/m2/.delivery/outbox"
for i in 1 2 3 4 5; do
  echo "{\"ts\":\"2026-09-05T11:0$i:00Z\",\"agent\":\"dm-builder\",\"slice\":\"old\",\"status\":\"done\",\"note\":\"history $i\"}" >> "$T/m2/.delivery/runs.jsonl"
done
python3 - "$T/home/.delivery-machine/registry.json" "$T/m2" <<'EOF'
import json, sys
p = sys.argv[1]; r = json.load(open(p))
r["m2"] = {"dir": sys.argv[2], "session": "dm-m2", "port": 5, "ttyd_port": 6, "started": "x"}
json.dump(r, open(p, "w"))
EOF
env $ENV python3 "$FF" --once || fail "first pass over a fresh machine exited $?"
grep -q 'history ' "$T/calls.log" && fail "a fresh machine's whole ledger was replayed to the phone"
echo '{"ts":"2026-09-05T11:06:00Z","agent":"dm-builder","slice":"new","status":"done","note":"the first new line"}' >> "$T/m2/.delivery/runs.jsonl"
env $ENV python3 "$FF" --once || fail "pass after the fresh machine's new line exited $?"
grep -q 'the first new line' "$T/calls.log" || fail "the first line after registration was not posted"

echo "PASS test_fleet_feed"
