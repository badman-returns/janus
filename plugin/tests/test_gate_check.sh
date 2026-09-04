#!/usr/bin/env bash
# gate-check.sh — the scope gate. Two things are being tested and the second matters more than
# the first: (a) it denies once the accumulated set of touched files passes the threshold, or the
# moment a guarded file is touched, unless a checklist is approved; (b) it FAILS OPEN on anything
# it cannot understand. A hook that blocks every write when its config is malformed would take
# the whole machine down and look like Claude hanging.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/gate-check.sh"; CL="$HERE/../scripts/checklist.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"; fail(){ echo "FAIL test_gate_check: $1"; exit 1; }
mkdir -p .delivery; echo '{"project":"t"}' > .delivery/config.json

# one PreToolUse call for a Write to <path>
gc(){ printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" | bash "$S"; }
denied(){ printf '%s' "$1" | grep -q '"permissionDecision": "deny"'; }

# under the default threshold of 4: silence
for f in src/a.ts src/b.ts src/c.ts src/d.ts; do
  out=$(gc "$f") || fail "exit $? on $f"
  [ -z "$out" ] || fail "denied at $f, under the threshold: $out"
done
[ "$(wc -l < .delivery/.touched | tr -d ' ')" = 4 ] || fail ".touched should hold 4 paths: $(cat .delivery/.touched)"

# the same file again is not a new file — the set is of paths, not calls
out=$(gc src/a.ts); [ -z "$out" ] || fail "re-editing a counted file denied: $out"
[ "$(wc -l < .delivery/.touched | tr -d ' ')" = 4 ] || fail "duplicate path counted"

# the fifth one is where a task that started as one file stops
out=$(gc src/e.ts)
denied "$out" || fail "5th file not denied: $out"
printf '%s' "$out" | grep -q 'checklist.sh' || fail "deny reason does not tell the agent what to do: $out"
printf '%s' "$out" | grep -q '"hookEventName": "PreToolUse"' || fail "not a PreToolUse decision: $out"
# and it is re-evaluated every call, not once
out=$(gc src/f.ts); denied "$out" || fail "6th file allowed after a deny: $out"

# an approved checklist opens it — that is the whole escape hatch
bash "$CL" init growing "widen the auth check" "files>4" >/dev/null
out=$(gc src/g.ts); denied "$out" || fail "an UNapproved checklist opened the gate: $out"
bash "$CL" approve growing >/dev/null
out=$(gc src/h.ts); [ -z "$out" ] || fail "approved checklist still denied: $out"

# the approval must be for the slice in flight (the ledger's last line), not any old slice
printf '%s\n' '{"ts":"2026-01-01T00:00:00Z","agent":"dm-builder","slice":"other","status":"dispatched","note":"x"}' > .delivery/runs.jsonl
out=$(gc src/i.ts); denied "$out" || fail "approval for 'growing' opened the gate while 'other' is in flight: $out"
bash "$CL" init other "the slice actually running" >/dev/null; bash "$CL" approve other >/dev/null
out=$(gc src/j.ts); [ -z "$out" ] || fail "approval for the in-flight slice did not open the gate: $out"

# a guarded file trips it immediately, whatever the count — fresh project, one file
T2=$(mktemp -d); (
  cd "$T2"; mkdir -p .delivery; echo '{"project":"t"}' > .delivery/config.json
  out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$T2/plugin/scripts/run-log.sh" | bash "$S")
  denied "$out" || { echo "guarded file not denied on the first touch: $out"; exit 1; }
  printf '%s' "$out" | grep -q "guarded" || { echo "deny reason does not say it was guarded: $out"; exit 1; }
  out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$T2/README.md" | bash "$S")
  [ -z "$out" ] || { echo "an unguarded file was denied at 2 of 4: $out"; exit 1; }
  # config can widen or narrow both knobs
  echo '{"project":"t","gate":{"max_files":1,"guarded":["*.env"]}}' > .delivery/config.json
  out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$T2/plugin/scripts/run-log.sh" | bash "$S")
  [ -n "$out" ] || { echo "max_files 1 with 2 already touched should deny"; exit 1; }
  printf '%s' "$out" | grep -q "past the gate of 1" || { echo "custom max_files not used: $out"; exit 1; }
) || fail "guarded/config case failed (see above)"
rm -rf "$T2"

# ---- fail open ------------------------------------------------------------------------------
# back to a slice nobody has approved, so the gate is live again
printf '%s\n' '{"ts":"2026-01-01T00:03:00Z","agent":"dm-builder","slice":"unapproved","status":"dispatched","note":"x"}' >> .delivery/runs.jsonl
out=$(gc src/z.ts); denied "$out" || fail "gate not live again for an unapproved slice: $out"

# malformed config: we cannot know the project's intent, so the write goes through
echo '{"project": "t", ' > .delivery/config.json
out=$(gc src/k.ts) || fail "malformed config exited $?"
[ -z "$out" ] || fail "malformed config blocked the write instead of failing open: $out"
grep -q "failed open" .delivery/pickup.log || fail "failure not noted in pickup.log: $(cat .delivery/pickup.log 2>&1)"
# ...and the touch was still recorded, so the gate works again the moment the config is fixed
grep -q "src/k.ts" .delivery/.touched || fail "touch not recorded while failing open"
echo '{"project":"t"}' > .delivery/config.json
out=$(gc src/l.ts); denied "$out" || fail "gate did not resume once the config parsed: $out"

# hook JSON that is not JSON, and a tool call with no file_path
out=$(echo 'not json' | bash "$S") || fail "bad stdin exited $?"
[ -z "$out" ] || fail "bad stdin produced a decision: $out"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$S") || fail "no file_path exited $?"
[ -z "$out" ] || fail "a call with no file_path was gated: $out"

# outside a Janus project: nothing at all, not even a .touched
cd /; out=$(gc /tmp/x.ts) || fail "outside a project exited $?"
[ -z "$out" ] || fail "gated outside a Janus project: $out"

# session-start.sh clears the set, so the count is per session
cd "$T"; bash "$HERE/../scripts/session-start.sh" >/dev/null 2>&1
[ ! -e .delivery/.touched ] || fail "session-start.sh did not clear .touched"
out=$(gc src/m.ts); [ -z "$out" ] || fail "first file of a new session denied: $out"

echo "PASS test_gate_check"
