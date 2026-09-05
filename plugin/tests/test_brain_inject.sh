#!/usr/bin/env bash
# session-start.sh prints the brain index and METHOD when ~/.delivery-machine/brain points at a repo.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SS="$HERE/../scripts/session-start.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL test_brain_inject: $1"; exit 1; }
mkdir -p "$T/brain/wiki/method" "$T/proj/.delivery" "$T/home/.delivery-machine"
echo '# index' > "$T/brain/index.md"; echo 'RULE-MARKER' > "$T/brain/wiki/method/METHOD.md"
echo "$T/brain" > "$T/home/.delivery-machine/brain"
echo '{"project":"x","services":{}}' > "$T/proj/.delivery/config.json"
OUT=$(cd "$T/proj" && HOME="$T/home" bash "$SS" 2>/dev/null)
echo "$OUT" | grep -q 'RULE-MARKER' || fail "METHOD not injected"
echo "$OUT" | grep -q '# index' || fail "index not injected"
rm "$T/home/.delivery-machine/brain"
OUT=$(cd "$T/proj" && HOME="$T/home" bash "$SS" 2>/dev/null) || fail "session-start failed without a brain"
echo "$OUT" | grep -q 'RULE-MARKER' && fail "injected without a brain pointer"
echo "PASS test_brain_inject"
