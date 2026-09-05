#!/usr/bin/env bash
# The mechanical half of the feeder: given in-flight checklists and two extracted changes, one that
# contradicts an approved item opens a gate file, one that does not becomes a note. (The extraction
# itself is LLM work in the concierge skill; this test fixes the file contract it must honour.)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; FR="$HERE/../scripts/fleet-route.sh"; IF="$HERE/../scripts/inflight.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_feeder_fixture: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/m/.delivery/inbox" "$T/m/.delivery/checklist"
echo "{\"m\":{\"dir\":\"$T/m\",\"session\":\"dm-m\"}}" > "$T/home/.delivery-machine/registry.json"
echo '{"ts":"t","agent":"dm-builder","slice":"desk-scheduling","status":"dispatched","note":"BT-11"}' > "$T/m/.delivery/runs.jsonl"
echo '{"slice":"desk-scheduling","intent":"back-dating with no upper bound (D-8)","gated":true,"approved_at":"2026-09-04T17:00:00Z","items":[{"text":"back-dating has no upper bound","proof":"api test","done":false,"ts":null}]}' > "$T/m/.delivery/checklist/desk-scheduling.json"
INF=$(HOME="$T/home" bash "$IF"); echo "$INF" | grep -q '"slice": "desk-scheduling"' || fail "inflight missing slice"
# contradiction -> gate file written by the concierge (this is the exact file shape the skill must produce)
printf 'GATE — meeting changes an approved default for desk-scheduling\n\nmeeting: raw/meetings/2026-09-05-field.md\napproved: back-dating has no upper bound (D-8)\nheard: seven days at most\n\nAPPROVE (adopt the change) / REJECT with note\n' > "$T/m/.delivery/inbox/gate-meeting-backdating-cap.txt"
# non-contradiction -> note
HOME="$T/home" FEED_CHAT_ID=1 bash "$FR" m "meeting 2026-09-05: reception asks to drop the Booked-outside-schedule badge on the desk; not in flight; plan as a slice" >/dev/null || fail "route failed"
[ "$(ls "$T/m/.delivery/inbox" | grep -c '^gate-meeting-')" = 1 ] || fail "gate count"
[ "$(ls "$T/m/.delivery/inbox" | grep -c '^note-.*-tg-meeting-2026-09-05')" = 1 ] || fail "note count: $(ls "$T/m/.delivery/inbox")"
grep -q 'approved: back-dating has no upper bound' "$T/m/.delivery/inbox/gate-meeting-backdating-cap.txt" || fail "gate body"
echo "PASS test_feeder_fixture"
