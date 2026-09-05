#!/usr/bin/env bash
# fleet-feed.py: a ledger line becomes one short message; a gate file becomes a card once; an outbox
# file is sent by type and moved to sent/. Telegram is a local stub that records every request.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; FF="$HERE/../scripts/fleet-feed.py"
T=$(mktemp -d); trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_fleet_feed: $1"; exit 1; }
cat > "$T/stub.py" <<'EOF'
import http.server, json, sys, re, urllib.parse
LOG = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(n)
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
env $ENV python3 "$FF" --once || fail "first pass exited $?"
grep -q '"method": "sendMessage"' "$T/calls.log" || fail "no sendMessage"
grep -q 'm1 · desk · dm-verifier done · PASS — api 887/887.' "$T/calls.log" || fail "ledger headline wrong: $(cat "$T/calls.log")"
grep -c 'GATE 2' "$T/calls.log" | grep -qx 1 || fail "gate card not sent exactly once"
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
echo "PASS test_fleet_feed"
