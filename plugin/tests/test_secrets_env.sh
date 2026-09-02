#!/usr/bin/env bash
# secrets-env.sh: keychain item → export line, single-quote escaped; missing item → warning, no export.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/secrets-env.sh"
T=$(mktemp -d); trap 'rm -rf "$T"; security delete-generic-password -s dm:sectest:tok >/dev/null 2>&1' EXIT
mkdir -p "$T/.delivery"; cd "$T"; fail(){ echo "FAIL test_secrets_env: $1"; exit 1; }
security add-generic-password -a "$USER" -s "dm:sectest:tok" -w "$(printf 'hello world' | base64)" -U || fail "keychain add"
echo '{"project":"sectest","services":{},"secrets":{"TOK":"tok"}}' > .delivery/config.json
out=$(bash "$S" 2>err); [ "$out" = "export TOK='hello world'" ] || fail "output: $out / $(cat err)"
security add-generic-password -a "$USER" -s "dm:sectest:tok" -w "$(printf "it's\n" | base64)" -U >/dev/null || fail "keychain update"
out=$(bash "$S"); [ "$out" = "export TOK='it'\\''s'" ] || fail "quote escaping: $out"
eval "$out"; [ "$TOK" = "it's" ] || fail "eval round-trip: $TOK"
echo '{"project":"sectest","services":{},"secrets":{"TOK":"tok","GONE":"nothere"}}' > .delivery/config.json
out=$(bash "$S" 2>err) || fail "missing item made the script fail"
[ "$out" = "export TOK='it'\\''s'" ] || fail "missing item changed output: $out"
grep -q "dm:sectest:nothere" err || fail "no warning for missing item: $(cat err)"
echo "PASS test_secrets_env"
