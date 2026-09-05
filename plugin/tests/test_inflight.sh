#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; IF="$HERE/../scripts/inflight.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_inflight: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/a/.delivery/checklist" "$T/b/.delivery"
echo "{\"a\":{\"dir\":\"$T/a\",\"session\":\"dm-a\"},\"b\":{\"dir\":\"$T/b\",\"session\":\"dm-b\"}}" > "$T/home/.delivery-machine/registry.json"
echo '{"ts":"t","agent":"dm-builder","slice":"s1","status":"built","note":"n"}' > "$T/a/.delivery/runs.jsonl"
echo '{"slice":"s1","intent":"i","gated":false,"approved_at":null,"items":[{"text":"x","proof":"y","done":false,"ts":null}]}' > "$T/a/.delivery/checklist/s1.json"
echo '{"ts":"t","agent":"dm-verifier","slice":"s9","status":"done","note":"n"}' > "$T/b/.delivery/runs.jsonl"
OUT=$(HOME="$T/home" bash "$IF") || fail "exited $?"
echo "$OUT" | python3 -c "
import json,sys; d=json.load(sys.stdin)
assert len(d)==1, d; assert d[0]['project']=='a' and d[0]['slice']=='s1' and d[0]['status']=='built'
assert d[0]['checklist']['items'][0]['proof']=='y'" || fail "json shape: $OUT"
echo "PASS test_inflight"
