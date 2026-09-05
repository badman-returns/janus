#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; PL="$HERE/../scripts/pickup-line.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_pickup_line: $1"; exit 1; }
DM="/dm process the pending items in .delivery/inbox"
CO="/concierge process the pending items in .delivery/inbox"
mkdir -p "$T/p/.delivery"

echo '{"project":"p"}' > "$T/p/.delivery/config.json"
OUT=$(cd "$T/p" && bash "$PL") || fail "no key exited $?"
[ "$OUT" = "$DM" ] || fail "no key: $OUT"

echo '{"project":"p","pickup_skill":"concierge"}' > "$T/p/.delivery/config.json"
OUT=$(cd "$T/p" && bash "$PL") || fail "concierge exited $?"
[ "$OUT" = "$CO" ] || fail "concierge: $OUT"

printf 'not json {\n' > "$T/p/.delivery/config.json"
OUT=$(cd "$T/p" && bash "$PL") || fail "bad json exited $?"
[ "$OUT" = "$DM" ] || fail "bad json: $OUT"

rm -f "$T/p/.delivery/config.json"
OUT=$(cd "$T/p" && bash "$PL") || fail "no config exited $?"
[ "$OUT" = "$DM" ] || fail "no config: $OUT"

echo "PASS test_pickup_line"
