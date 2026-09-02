#!/usr/bin/env bash
# run-log.sh / dm-gate.sh: done only from dm-verifier with proof newer than the slice's newest commit.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; RL="$HERE/../scripts/run-log.sh"; GATE="$HERE/../scripts/dm-gate.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"; fail(){ echo "FAIL test_run_log: $1"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q && git checkout -q -b fix/x-slice && echo a > a && git add a && git commit -qm one
mkdir -p .delivery; : > .delivery/runs.jsonl
G=.delivery/inbox/gate-x-slice-proof.txt
lines(){ wc -l < .delivery/runs.jsonl | tr -d ' '; }
last(){ tail -1 .delivery/runs.jsonl | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['agent'],d['status'])"; }

bash "$RL" dm-builder x-slice done "nope" 2>/dev/null; [ $? -eq 2 ] || fail "builder done not refused"
[ "$(lines)" = 0 ] || fail "refused done still written"
bash "$RL" dm-verifier x-slice done "no proof" 2>err; [ $? -eq 2 ] || fail "verifier done without proof not refused"
grep -q missing err || fail "missing-README reason not given: $(cat err)"
bash "$GATE" x-slice 2>/dev/null && fail "gate opened without proof"
[ ! -e "$G" ] || fail "gate file written without proof"

mkdir -p proof/x-slice; echo proof > proof/x-slice/README.md
bash "$RL" dm-verifier x-slice done "proven" || fail "fresh proof refused"
[ "$(lines)" = 1 ] || fail "done not appended"
[ "$(last)" = "dm-verifier done" ] || fail "wrong line appended: $(tail -1 .delivery/runs.jsonl)"
bash "$GATE" x-slice || fail "gate refused fresh proof"
[ -f "$G" ] || fail "gate file missing"
grep -q '^GATE 2 — review proof for x-slice' "$G" || fail "gate heading"
grep -q 'fix/x-slice' "$G" && grep -q 'README.md' "$G" || fail "gate body: $(cat "$G")"
rm "$G"

sleep 1; echo b > a; git commit -qam two   # commit now newer than the README
bash "$RL" dm-verifier x-slice done "stale" 2>err; [ $? -eq 2 ] || fail "stale proof accepted after new commit"
grep -q older err || fail "stale reason not given: $(cat err)"
bash "$GATE" x-slice 2>/dev/null && fail "gate opened on stale proof"
[ ! -e "$G" ] || fail "gate file written on stale proof"
[ "$(lines)" = 1 ] || fail "stale done written"
touch proof/x-slice/README.md
bash "$RL" dm-verifier x-slice done "fresh again" || fail "re-touched proof refused"
[ "$(lines)" = 2 ] || fail "second done not appended"

bash "$RL" dm-builder x-slice built "built it" || fail "builder built refused"
[ "$(last)" = "dm-builder built" ] || fail "built line wrong: $(tail -1 .delivery/runs.jsonl)"
bash "$RL" dm-builder x-slice bogus "x" 2>/dev/null; [ $? -eq 2 ] || fail "unknown status accepted"
[ "$(lines)" = 3 ] || fail "ledger has $(lines) lines, expected 3"

# agent names were unchecked, so typos became permanent distinct actors in the ledger.
# The rule is the one already in use: orchestrator, or dm-<role> in lowercase.
bash "$RL" orchestrator x-slice working "planning" || fail "orchestrator refused"
bash "$RL" dm-scenario-writer x-slice working "a project's own role" || fail "dm-<role> refused"
for bad in builder dm_builder dm-Builder DM-BUILDER "" "dm-build er"; do
  bash "$RL" "$bad" x-slice working "x" 2>/dev/null && fail "accepted bad agent '$bad'"
done
[ "$(lines)" = 5 ] || fail "bad agents reached the ledger: $(lines) lines, expected 5"

echo "PASS test_run_log"
