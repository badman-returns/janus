#!/usr/bin/env bash
# foundry.sh on real ledger lines: 3 fails on one slice, or a 40-char note prefix 3x → candidate; 2x → nothing.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/foundry.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.delivery"; cd "$T"; fail(){ echo "FAIL test_foundry: $1"; exit 1; }
L=.delivery/runs.jsonl; C=.delivery/skill-candidates
line(){ echo "{\"ts\":\"2026-09-02T10:00:0${5:-0}Z\",\"agent\":\"$1\",\"slice\":\"$2\",\"status\":\"$3\",\"note\":\"$4\"}" >> $L; }
cands(){ ls $C/cand-*.md 2>/dev/null | wc -l | tr -d ' '; }

line dm-builder login working "started"
line dm-reviewer login failed "no tests"
line dm-reviewer login failed "still no tests"
line dm-verifier login done "proven"
bash "$S" >/dev/null || fail "exit $?"
[ "$(cands)" = 0 ] || fail "2 repeats produced a candidate: $(cat $C/*)"

line dm-reviewer login failed "tests, but flaky"
bash "$S" >/dev/null || fail "exit $?"
[ "$(cands)" = 1 ] || fail "3 fails on one slice: $(cands) candidates"
grep -q 'dm-reviewer failed on login' $C/cand-*.md || fail "pattern not named: $(cat $C/*)"
bash "$S" >/dev/null; [ "$(cands)" = 1 ] || fail "rerun duplicated the candidate"

P="migration needs the sensitive db up before" # 40 chars; each note differs after it
line dm-builder cases failed "$P it can run" 1
line dm-builder notes failed "$P vitest starts" 2
bash "$S" >/dev/null; [ "$(cands)" = 1 ] || fail "note prefix seen twice produced a candidate"
line dm-verifier tally built "$P proof" 3
bash "$S" >/dev/null || fail "exit $?"
[ "$(cands)" = 2 ] || fail "note prefix 3x across slices: $(cands) candidates"
grep -qF "$P" $C/cand-*.md || fail "note prefix not named: $(cat $C/*)"
echo "PASS test_foundry"
