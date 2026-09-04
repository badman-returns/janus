#!/usr/bin/env bash
# `dispatched` — an agent has been HANDED a slice and is running now. run-log.sh is only ever
# called after an agent finishes, so an in-flight agent was invisible. The status has to be
# known to run-log.sh AND to ledger-verify.sh (which rejects unknown statuses), and it must
# never be mistaken for done: no proof rule applies to it, and none of done's rules relax.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; RL="$HERE/../scripts/run-log.sh"; V="$HERE/../scripts/ledger-verify.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"; fail(){ echo "FAIL test_dispatched: $1"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q && echo a > a && git add a && git commit -qm one
mkdir -p .delivery; echo '{"project":"t"}' > .delivery/config.json; : > .delivery/runs.jsonl
lines(){ wc -l < .delivery/runs.jsonl | tr -d ' '; }
last(){ tail -1 .delivery/runs.jsonl | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['agent'],d['status'])"; }
L(){ bash "$V" 2>&1; }

# 1. run-log.sh accepts it, from any agent, with no proof anywhere on disk
bash "$RL" dm-builder login dispatched "builder handed login" || fail "dispatched refused"
[ "$(last)" = "dm-builder dispatched" ] || fail "wrong line: $(tail -1 .delivery/runs.jsonl)"
bash "$RL" orchestrator login dispatched "spawned the builder" || fail "orchestrator dispatched refused"
bash "$RL" dm-verifier login dispatched "verifier running" || fail "verifier dispatched refused"
[ "$(lines)" = 3 ] || fail "expected 3 lines, got $(lines)"
[ -e proof ] && fail "dispatched should not require or create proof"

# 2. it is exactly five fields, like every other line
tail -1 .delivery/runs.jsonl | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert sorted(d)==['agent','note','slice','status','ts'], sorted(d)" || fail "line shape changed"

# 3. ledger-verify.sh accepts dispatched lines written straight to the file
bash "$V" >/dev/null 2>&1 || fail "ledger-verify rejected dispatched: $(L)"
printf '%s\n' '{"ts":"2026-01-01T00:00:00Z","agent":"dm-scenario-writer","slice":"login","status":"dispatched","note":"x"}' >> .delivery/runs.jsonl
bash "$V" >/dev/null 2>&1 || fail "ledger-verify rejected a hand-written dispatched: $(L)"

# 4. dispatched does NOT satisfy done: the slice is still not done, and the old rules stand
bash "$RL" dm-builder login done "dispatched, therefore done" 2>/dev/null; [ $? -eq 2 ] || fail "done from builder accepted"
bash "$RL" dm-verifier login done "no proof" 2>/dev/null; [ $? -eq 2 ] || fail "done without proof accepted after a dispatch"
[ "$(lines)" = 4 ] || fail "a refused done reached the ledger: $(lines) lines"

# 5. the statuses that were never real are still rejected — the negative case this had to not break
bash "$RL" dm-builder login gate "x" 2>/dev/null; [ $? -eq 2 ] || fail "'gate' status accepted by run-log"
bash "$RL" dm-builder login dispatch "x" 2>/dev/null; [ $? -eq 2 ] || fail "'dispatch' (near-miss) accepted"
printf '%s\n' '{"ts":"2026-01-01T00:01:00Z","agent":"dm-verifier","slice":"login","status":"gate","note":"g"}' >> .delivery/runs.jsonl
L | grep -q "status 'gate'" || fail "ledger-verify no longer catches the 'gate' status: $(L)"
printf '%s\n' '{"ts":"2026-01-01T00:02:00Z","agent":"orchestrator","slice":"login","status":"done","note":"me"}' >> .delivery/runs.jsonl
L | grep -q "only dm-verifier" || fail "ledger-verify no longer catches a forged done: $(L)"

echo "PASS test_dispatched"
