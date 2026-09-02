#!/usr/bin/env bash
# GET /api/slice?name=x: ledger lines, spec, branch and proof for one slice, from a throwaway project.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SRV="$HERE/../../plugin-mc/mission-control/server.js"
T=$(mktemp -d); PORT=5599; PID=""
trap '[ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$T"' EXIT
cd "$T"; fail(){ echo "FAIL test_slice_api: $1"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q && git checkout -q -b fix/x && echo a > a && git add a && git commit -qm one
mkdir -p .delivery .planning/specs proof/x
echo '{"project":"t"}' > .delivery/config.json
printf '%s\n' '{"ts":"2026-01-01T00:00:00Z","agent":"dm-builder","slice":"x","status":"built","note":"b"}' \
               '{"ts":"2026-01-01T00:01:00Z","agent":"dm-verifier","slice":"x","status":"done","note":"v"}' \
               '{"ts":"2026-01-01T00:02:00Z","agent":"dm-builder","slice":"y","status":"built","note":"other"}' > .delivery/runs.jsonl
echo '# x' > .planning/specs/2026-x.md
echo 'proof of x' > proof/x/README.md

node "$SRV" --port $PORT --project "$T" --session dm-none >/dev/null 2>&1 & PID=$!; disown
for i in $(seq 1 40); do curl -sf "localhost:$PORT/api/state" >/dev/null && break; sleep 0.25; done
curl -sf "localhost:$PORT/api/state" >/dev/null || fail "server did not come up on $PORT"

curl -sf "localhost:$PORT/api/slice?name=x" > out.json || fail "slice endpoint failed"
python3 - out.json <<'EOF' || fail "assertions"
import json,sys; d=json.load(open(sys.argv[1]))
assert d["slice"]=="x", d
assert len(d["runs"])==2 and [r["status"] for r in d["runs"]]==["built","done"], d["runs"]
assert d["spec"]["name"]=="2026-x.md" and d["spec"]["body"].startswith("# x"), d["spec"]
assert d["branch"]["name"]=="fix/x" and d["branch"]["commits"][0]["subject"]=="one", d["branch"]
assert "README.md" in d["proof"]["files"] and d["proof"]["readme"].startswith("proof of x"), d["proof"]
EOF
[ "$(curl -s -o /dev/null -w '%{http_code}' "localhost:$PORT/api/slice?name=../x")" = 400 ] || fail "bad name not refused"
echo "PASS test_slice_api"
