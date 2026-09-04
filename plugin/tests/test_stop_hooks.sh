#!/usr/bin/env bash
# Two things about Stop. (1) handoff.sh runs there as well as on PreCompact — PreCompact only
# fires on compaction, so closing a terminal used to leave a handoff from hours ago and the
# operator had to ask for one. (2) foundry.sh runs on every Stop, which not every project
# wants; it now reads config "foundry" and no-ops on false — defaulting to TRUE so no existing
# project changes behaviour because the switch appeared.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; H="$HERE/../hooks/hooks.json"; F="$HERE/../scripts/foundry.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL test_stop_hooks: $1"; exit 1; }

# ---- wiring: hooks.json is the contract, so assert on it
cmds(){ python3 - "$H" "$1" "${2:-}" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))["hooks"].get(sys.argv[2], [])
want = sys.argv[3] if len(sys.argv) > 3 else ""
for e in h:
    if want and (e.get("matcher") or "") != want: continue
    for k in e["hooks"]: print(k["command"])
PY
}
python3 -c "import json;json.load(open('$H'))" || fail "hooks.json is not valid JSON"
cmds Stop | grep -q "handoff.sh" || fail "handoff.sh is not on Stop: $(cmds Stop)"
cmds Stop | grep -q "activity.sh" || fail "Stop lost activity.sh: $(cmds Stop)"
cmds Stop | grep -q "foundry.sh" || fail "Stop lost foundry.sh — another project uses it: $(cmds Stop)"
cmds PreCompact | grep -q "handoff.sh" || fail "PreCompact lost handoff.sh"
# the two new write-tool hooks, on the matcher they must have
cmds PreToolUse 'Write|Edit|NotebookEdit' | grep -q "gate-check.sh" || fail "gate-check.sh not on PreToolUse Write|Edit|NotebookEdit"
cmds PostToolUse 'Write|Edit|NotebookEdit' | grep -q "knowledge-log.sh" || fail "knowledge-log.sh not on PostToolUse Write|Edit|NotebookEdit"
cmds PreToolUse AskUserQuestion | grep -q "ask.sh" || fail "PreToolUse lost ask.sh"
cmds PostToolUse | grep -q "activity.sh" || fail "PostToolUse lost activity.sh"

# ---- the foundry switch
cd "$T"; mkdir -p .delivery
L=.delivery/runs.jsonl
for i in 1 2 3; do
  echo "{\"ts\":\"2026-09-02T10:00:0${i}Z\",\"agent\":\"dm-reviewer\",\"slice\":\"login\",\"status\":\"failed\",\"note\":\"n$i\"}" >> $L
done
cands(){ ls .delivery/skill-candidates/cand-*.md 2>/dev/null | wc -l | tr -d ' '; }

# no config at all: unchanged behaviour (this is how test_foundry's fixture looks)
bash "$F" >/dev/null || fail "exit $? with no config.json"
[ "$(cands)" = 1 ] || fail "no config.json should not disable the foundry: $(cands) candidates"
rm -rf .delivery/skill-candidates

# key absent, and an explicit true: still runs
echo '{"project":"t"}' > .delivery/config.json
bash "$F" >/dev/null || fail "exit $? with the key absent"
[ "$(cands)" = 1 ] || fail "absent key disabled the foundry"
rm -rf .delivery/skill-candidates
echo '{"project":"t","foundry":true}' > .delivery/config.json
bash "$F" >/dev/null || fail "exit $? with foundry:true"
[ "$(cands)" = 1 ] || fail "foundry:true disabled it"
rm -rf .delivery/skill-candidates

# malformed config keeps the old behaviour too — an opt-out must be explicit
echo '{"project":' > .delivery/config.json
bash "$F" >/dev/null || fail "exit $? with a malformed config"
[ "$(cands)" = 1 ] || fail "malformed config disabled the foundry"
rm -rf .delivery/skill-candidates

# and false is a silent no-op that writes nothing
echo '{"project":"t","foundry":false}' > .delivery/config.json
out=$(bash "$F") || fail "exit $? with foundry:false"
[ -z "$out" ] || fail "foundry:false printed: $out"
[ "$(cands)" = 0 ] || fail "foundry:false still wrote candidates"

echo "PASS test_stop_hooks"
