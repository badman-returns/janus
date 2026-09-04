#!/usr/bin/env bash
# checklist.sh writes .delivery/checklist/<slice>.json — the declaration a gated slice needs
# before it may keep going. The rule that matters: every item carries the proof that will show
# it was done, so `add` refuses an item without one. An item with no stated proof can never be
# honestly checked off, and a checklist of those is just a to-do list.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/checklist.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.delivery"; cd "$T"; fail(){ echo "FAIL test_checklist: $1"; exit 1; }
F=.delivery/checklist/login.json
j(){ python3 -c "import json,sys;print(eval('d'+sys.argv[1],{'d':json.load(open('$F'))}))" "$1"; }

# add before init is refused, and writes nothing
bash "$S" add login "a thing" "a proof" 2>/dev/null; [ $? -eq 2 ] || fail "add before init accepted"
[ -e $F ] && fail "refused add created the file"

bash "$S" init login "make login work" "files>4" "guarded:run-log.sh" >/dev/null || fail "init failed"
[ -f $F ] || fail "init wrote no file"
[ "$(j "['slice']")" = login ] || fail "slice wrong"
[ "$(j "['intent']")" = "make login work" ] || fail "intent not verbatim: $(j "['intent']")"
[ "$(j "['gated']")" = True ] || fail "gated should be true"
[ "$(j "['approved_at']")" = None ] || fail "approved_at should start null"
[ "$(j "['triggers']")" = "['files>4', 'guarded:run-log.sh']" ] || fail "triggers wrong: $(j "['triggers']")"
[ "$(j "['items']")" = "[]" ] || fail "items should start empty"

# an item with no proof is refused — the one rule this script exists to enforce
for bad in "" "   "; do
  bash "$S" add login "no proof for this" "$bad" 2>/dev/null; [ $? -eq 2 ] || fail "add accepted proof '$bad'"
done
bash "$S" add login "missing arg entirely" 2>/dev/null; [ $? -eq 2 ] || fail "add accepted a missing proof arg"
[ "$(j "['items']")" = "[]" ] || fail "a refused add appended anyway: $(j "['items']")"

bash "$S" add login "wire the form" "screenshot of a successful login" >/dev/null || fail "valid add refused"
bash "$S" add login "cover the error path" "test_login.sh fails without the guard" >/dev/null || fail "second add refused"
[ "$(j "['items'].__len__()")" = 2 ] || fail "expected 2 items"
[ "$(j "['items'][0]['done']")" = False ] || fail "item should start undone"
[ "$(j "['items'][0]['ts']")" = None ] || fail "ts should start null"
[ "$(j "['items'][1]['proof']")" = "test_login.sh fails without the guard" ] || fail "proof not stored"

# check stamps done + ts, and only the item named
bash "$S" check login 1 >/dev/null || fail "check refused"
[ "$(j "['items'][1]['done']")" = True ] || fail "check did not set done"
case "$(j "['items'][1]['ts']")" in 20*T*Z) : ;; *) fail "ts not ISO: $(j "['items'][1]['ts']")" ;; esac
[ "$(j "['items'][0]['done']")" = False ] || fail "check touched the wrong item"
bash "$S" check login 9 2>/dev/null; [ $? -eq 2 ] || fail "check accepted an out-of-range index"

# approve stamps approved_at — the only thing gate-check.sh reads
bash "$S" approve login >/dev/null || fail "approve refused"
case "$(j "['approved_at']")" in 20*T*Z) : ;; *) fail "approved_at not ISO: $(j "['approved_at']")" ;; esac

out=$(bash "$S" show login) || fail "show failed"
printf '%s' "$out" | grep -q "make login work" || fail "show omits the intent: $out"
printf '%s' "$out" | grep -q "screenshot of a successful login" || fail "show omits a proof: $out"
printf '%s' "$out" | grep -q "\[x\] 1" || fail "show does not mark the done item: $out"
printf '%s' "$out" | grep -q "\[ \] 0" || fail "show does not mark the open item: $out"

# unknown subcommand, and a slice name that would escape the directory
bash "$S" frobnicate login 2>/dev/null; [ $? -eq 2 ] || fail "unknown subcommand accepted"
bash "$S" init ../escape "nope" 2>/dev/null; [ $? -eq 2 ] || fail "slice name with a slash accepted"
cd /; bash "$S" show login 2>/dev/null; [ $? -eq 1 ] || fail "outside a Janus project should exit 1"

echo "PASS test_checklist"
