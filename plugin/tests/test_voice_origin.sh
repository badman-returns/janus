#!/usr/bin/env bash
# The loop's endpoint is for this machine, not for every page open in the browser. Binding 127.0.0.1
# keeps the network out, not the tabs on it: without an Origin check any page could read the whole
# conversation off /stream and post an instruction into /say. A request with no Origin (curl, the
# selftest, shell.py) and one from the fleet cockpit are answered; everything else is refused before
# the handler runs, on GET and on POST, and the allow header echoes the origin rather than `*`.
# Only the handler class runs here, on a free port, with numpy stubbed: no audio, no LOOP, and
# nothing that could reach the real loop on 8790.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; VOICE="$HERE/../../voice"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_voice_origin: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/fleet/.delivery"
echo '{"project": "originfleet"}' > "$T/fleet/.delivery/config.json"
cat > "$T/home/.delivery-machine/registry.json" <<JSON
{"originfleet": {"dir": "$T/fleet", "session": "dm-originfleet", "port": 5599}}
JSON

cd "$T/fleet" || fail "no fleet dir"
HOME="$T/home" VOICE="$VOICE" python3 - <<'PY' || fail "origin assertions failed (above)"
import os, sys, threading, types, urllib.error, urllib.request
from http.server import ThreadingHTTPServer
sys.modules.setdefault('numpy', types.ModuleType('numpy'))       # the handler touches no audio
sys.path.insert(0, os.environ['VOICE'])
import loop

assert loop.ALLOW == {'http://localhost:5599', 'http://127.0.0.1:5599'}, loop.ALLOW   # from the registry
srv = ThreadingHTTPServer(('127.0.0.1', 0), loop.H)              # a free port, never the loop's 8790
threading.Thread(target=srv.serve_forever, daemon=True).start()
port = srv.server_address[1]

def hit(path, origin=None, method='GET'):
    r = urllib.request.Request(f'http://127.0.0.1:{port}{path}', method=method,
                               data=b'{"text":"hello"}' if method == 'POST' else None)
    if origin: r.add_header('Origin', origin)
    try:
        with urllib.request.urlopen(r, timeout=10) as f: return f.getcode(), f.headers.get('Access-Control-Allow-Origin')
    except urllib.error.HTTPError as e: return e.code, e.headers.get('Access-Control-Allow-Origin')

COCKPIT, EVIL = 'http://localhost:5599', 'http://evil.example'
cases = [                                              # path, origin, method, wanted code, wanted echo
    ('/state', None,    'GET',  200, None),            # curl, selftest-room.sh, shell.py
    ('/state', COCKPIT, 'GET',  200, COCKPIT),         # the front page, served by mission control
    ('/state', EVIL,    'GET',  403, None),
    ('/stream', EVIL,   'GET',  403, None),            # the whole conversation, refused before a line of it
    ('/say',   EVIL,    'POST', 403, None),            # CORS-simple: no preflight would ever be asked
    ('/listen', EVIL,   'POST', 403, None),
    ('/stop',  EVIL,    'POST', 403, None),
]
for path, origin, method, code, echo in cases:
    got = hit(path, origin, method)
    assert got == (code, echo), f'{method} {path} from {origin!r}: got {got}, wanted {(code, echo)}'
print(f'ok: {len(cases)} cases; cockpit {COCKPIT} echoed, {EVIL} refused on /state, /stream and POST')
PY
echo "PASS test_voice_origin"
