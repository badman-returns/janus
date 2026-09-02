#!/usr/bin/env bash
# ledger-verify.sh re-derives the ledger's guarantees from disk. run-log.sh can refuse a bad
# write, but nothing stops an agent with a shell from appending straight to runs.jsonl — this
# is what makes that visible afterwards. Written after finding three such lines in real
# ledgers: two `done`s logged by the orchestrator and a `gate` status that does not exist.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; V="$HERE/../scripts/ledger-verify.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"; fail(){ echo "FAIL test_ledger_verify: $1"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q && echo a > a && git add a && git commit -qm one
mkdir -p .delivery proof/good
echo '{"project":"t"}' > .delivery/config.json
echo 'proof' > proof/good/README.md

add(){ printf '%s\n' "$1" >> .delivery/runs.jsonl; }   # deliberately bypassing run-log.sh
L(){ bash "$V" 2>&1; }

# a clean ledger passes
add '{"ts":"2026-01-01T00:00:00Z","agent":"dm-builder","slice":"good","status":"built","note":"b"}'
add '{"ts":"2026-01-01T00:01:00Z","agent":"dm-verifier","slice":"good","status":"done","note":"v"}'
bash "$V" >/dev/null 2>&1 || fail "clean ledger reported violations: $(L)"

# a done nobody verified — the case that actually matters
add '{"ts":"2026-01-01T00:02:00Z","agent":"orchestrator","slice":"good","status":"done","note":"me"}'
bash "$V" >/dev/null 2>&1 && fail "forged done by orchestrator accepted"
L | grep -q "line 3" || fail "did not name the forged line: $(L)"
L | grep -q "only dm-verifier" || fail "did not say why: $(L)"

# a status run-log.sh would reject
add '{"ts":"2026-01-01T00:03:00Z","agent":"dm-verifier","slice":"good","status":"gate","note":"g"}'
L | grep -q "status 'gate'" || fail "off-protocol status not caught: $(L)"

# an agent name that is not orchestrator or dm-<role>
add '{"ts":"2026-01-01T00:04:00Z","agent":"builder","slice":"good","status":"built","note":"x"}'
L | grep -q "is not orchestrator or dm-<role>" || fail "bad agent not caught: $(L)"

# a shape run-log.sh never produces
add '{"ts":"2026-01-01T00:05:00Z","agent":"dm-builder","slice":"good","status":"built"}'
L | grep -q "missing field" || fail "missing field not caught: $(L)"
add 'not json at all'
L | grep -q "not JSON" || fail "non-JSON line not caught: $(L)"

# a done whose proof went stale after the fact still fails, even though it passed on the way in
rm -rf proof/good
L | grep -q "no longer holds" || fail "done with vanished proof not caught: $(L)"
mkdir -p proof/good && echo 'proof' > proof/good/README.md

# the baseline collapses history so the tool stays readable on an existing ledger
bash "$V" --accept "2026-01-01T00:10:00Z" >/dev/null || fail "--accept failed"
[ -f .delivery/ledger-baseline ] || fail "--accept wrote no baseline"
out=$(L)
printf '%s' "$out" | grep -qE "history, not listed|predate the rules" || fail "baseline did not summarise history: $out"
printf '%s' "$out" | grep -q "line 3" && fail "baselined line still listed individually: $out"

# and a violation after the baseline is still reported in full
add '{"ts":"2026-02-02T00:00:00Z","agent":"orchestrator","slice":"good","status":"done","note":"late"}'
out=$(L)
printf '%s' "$out" | grep -q "only dm-verifier" || fail "post-baseline forgery not reported: $out"

# no ledger at all is not a failure
rm .delivery/runs.jsonl
bash "$V" >/dev/null 2>&1 || fail "missing ledger should exit 0"

echo "PASS test_ledger_verify"
