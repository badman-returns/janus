#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; IF="$HERE/../scripts/inflight.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_inflight: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/a/.delivery/checklist" "$T/b/.delivery"
echo "{\"a\":{\"dir\":\"$T/a\",\"session\":\"dm-a\"},\"b\":{\"dir\":\"$T/b\",\"session\":\"dm-b\"}}" > "$T/home/.delivery-machine/registry.json"
{ echo '{"ts":"t","agent":"dm-builder","slice":"s1","status":"built","note":"n"}'
  echo '{"ts":"t","agent":"orchestrator","slice":"s0","status":"failed","note":"abandoned months ago"}'
  echo '{"ts":"t","agent":"dm-architect","slice":"s2","status":"dispatched","note":"in flight now"}'
} > "$T/a/.delivery/runs.jsonl"
echo '{"slice":"s1","intent":"i","gated":false,"approved_at":null,"items":[{"text":"x","proof":"y","done":false,"ts":null}]}' > "$T/a/.delivery/checklist/s1.json"
echo '{"ts":"t","agent":"dm-verifier","slice":"s9","status":"done","note":"n"}' > "$T/b/.delivery/runs.jsonl"
OUT=$(HOME="$T/home" bash "$IF") || fail "exited $?"
echo "$OUT" | python3 -c "
import json,sys; d=json.load(sys.stdin); by={e['slice']: e for e in d}
# s1 promises a checklist; s2 is the ledger's last line (in flight, nothing promised yet);
# s0 promised nothing and is not in flight; b's only line is done
assert set(by) == {'s1','s2'}, d
assert by['s1']['project']=='a' and by['s1']['status']=='built'
assert by['s1']['checklist']['items'][0]['proof']=='y'
assert by['s2']['status']=='dispatched' and by['s2']['checklist'] is None" || fail "json shape: $OUT"
echo "PASS test_inflight"
