#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; FS="$HERE/../scripts/fleet-status.sh"; FR="$HERE/../scripts/fleet-route.sh"; FG="$HERE/../scripts/fleet-gate.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_fleet_status: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/a/.delivery/inbox" "$T/a/.delivery/checklist" "$T/a/.delivery/agents" "$T/b/.delivery/inbox"
echo "{\"a\":{\"dir\":\"$T/a\",\"session\":\"dm-a\",\"port\":1,\"ttyd_port\":2,\"started\":\"x\"},\"b\":{\"dir\":\"$T/b\",\"session\":\"dm-b\",\"port\":3,\"ttyd_port\":4,\"started\":\"x\"}}" > "$T/home/.delivery-machine/registry.json"
echo '{"ts":"2026-09-05T10:00:00Z","agent":"dm-builder","slice":"s1","status":"dispatched","note":"round 1"}' > "$T/a/.delivery/runs.jsonl"
echo '{"slice":"s1","intent":"do it","gated":true,"approved_at":"2026-09-05T09:00:00Z","items":[{"text":"a","proof":"p","done":true,"ts":"x"},{"text":"b","proof":"q","done":false,"ts":null}]}' > "$T/a/.delivery/checklist/s1.json"
printf 'GATE 2 — review proof for s1\n' > "$T/a/.delivery/inbox/gate-s1-proof.txt"
echo '{"sid":"1","ts":"now"}' > "$T/a/.delivery/agents/1.json"
OUT=$(HOME="$T/home" bash "$FS") || fail "status exited $?"
echo "$OUT" | grep -q '^a · personal · live · dm-builder dispatched s1 · gates:1 · checklist 1/2' || fail "status line: $OUT"
HOME="$T/home" FEED_CHAT_ID=42 bash "$FR" a "please pause slice s1" || fail "route exited $?"
N=$(ls "$T/a/.delivery/inbox" | grep -c '^note-[0-9]*-tg-please-pause-slice-s1.txt$'); [ "$N" = 1 ] || fail "note not written: $(ls "$T/a/.delivery/inbox")"
head -1 "$T"/a/.delivery/inbox/note-*-tg-*.txt | grep -q '^from: telegram 42 20' || fail "note header: $(head -1 "$T"/a/.delivery/inbox/note-*-tg-*.txt)"
HOME="$T/home" bash "$FG" a REJECT "badge text wrong" || fail "gate exited $?"
[ ! -e "$T/a/.delivery/inbox/gate-s1-proof.txt" ] || fail "gate file not removed"
R=$(ls "$T/a/.delivery/inbox" | grep '^reply-'); [ -n "$R" ] || fail "no reply file"
head -1 "$T/a/.delivery/inbox/$R" | grep -qx 'RE: gate-s1-proof.txt' || fail "reply line 1: $(head -1 "$T/a/.delivery/inbox/$R")"
sed -n 2p "$T/a/.delivery/inbox/$R" | grep -qx 'REJECT: badge text wrong' || fail "reply line 2"
HOME="$T/home" bash "$FG" a APPROVE 2>/dev/null && fail "approve with no gate should fail"

# a machine name is operator input: it must never reach python source, and never be trusted
POC="a']); import os; os.system('touch $T/pwned') #"
HOME="$T/home" bash "$FR" "$POC" hi >/dev/null 2>&1; [ $? = 1 ] || fail "route took a bad machine name"
HOME="$T/home" bash "$FR" "$POC" hi 2>&1 | grep -qx 'fleet-route: bad machine name' || fail "route bad-name message"
HOME="$T/home" bash "$FG" "$POC" APPROVE >/dev/null 2>&1; [ $? = 1 ] || fail "gate took a bad machine name"
HOME="$T/home" bash "$FG" "$POC" APPROVE 2>&1 | grep -qx 'fleet-gate: bad machine name' || fail "gate bad-name message"
[ ! -e "$T/pwned" ] || fail "INJECTION EXECUTED — the name reached python source"
HOME="$T/home" bash "$FR" nope hi >/dev/null 2>&1; [ $? = 1 ] || fail "route took an unknown machine"
HOME="$T/home" bash "$FR" nope hi 2>&1 | grep -qx 'fleet-route: no machine nope' || fail "route unknown message"
HOME="$T/home" bash "$FG" nope APPROVE 2>&1 | grep -qx 'fleet-gate: no machine nope' || fail "gate unknown message"

# "approve latest" — the newest gate on ANY machine, answered there and nowhere else
printf 'GATE 2 — review proof for s2\n' > "$T/a/.delivery/inbox/gate-s2-proof.txt"; sleep 1
printf 'GATE 2 — review proof for s3\n' > "$T/b/.delivery/inbox/gate-s3-proof.txt"
HOME="$T/home" bash "$FG" latest APPROVE || fail "latest exited $?"
[ ! -e "$T/b/.delivery/inbox/gate-s3-proof.txt" ] || fail "latest did not answer b's newer gate"
[ -e "$T/a/.delivery/inbox/gate-s2-proof.txt" ] || fail "latest also removed a's older gate"
RB=$(ls "$T/b/.delivery/inbox" | grep '^reply-')
head -1 "$T/b/.delivery/inbox/$RB" | grep -qx 'RE: gate-s3-proof.txt' || fail "latest reply line 1"
sed -n 2p "$T/b/.delivery/inbox/$RB" | grep -qx 'APPROVE' || fail "bare approve is not the protocol's APPROVE"
# an approval carrying the operator's ruling keeps it in the reply, for the orchestrator to record
HOME="$T/home" bash "$FG" a APPROVE "ship it" || fail "approve with a note exited $?"
RA=$(ls "$T/a/.delivery/inbox" | grep '^reply-.*gate-s2' )
sed -n 2p "$T/a/.delivery/inbox/$RA" | grep -qx 'APPROVE — ship it' || fail "approve note dropped"
# the gate card tells the operator to type `/gate approve <proj>`, so a lowercase verdict must work
printf 'GATE 2 — review proof for s4\n' > "$T/a/.delivery/inbox/gate-s4-proof.txt"
HOME="$T/home" bash "$FG" a approve "lower case" || fail "lowercase approve exited $?"
R4=$(ls "$T/a/.delivery/inbox" | grep '^reply-.*gate-s4')
sed -n 2p "$T/a/.delivery/inbox/$R4" | grep -qx 'APPROVE — lower case' || fail "lowercase verdict not upper-cased"
HOME="$T/home" bash "$FG" latest APPROVE >/dev/null 2>&1; [ $? = 2 ] || fail "latest with nothing waiting should exit 2"
echo "PASS test_fleet_status"
