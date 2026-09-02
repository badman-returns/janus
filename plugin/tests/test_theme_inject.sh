#!/usr/bin/env bash
# server.js renders theme.json into :root blocks; light block guarded by [data-theme=light].
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
out=$(node "$HERE/../../plugin-mc/mission-control/server.js" --render-tokens)
fail(){ echo "FAIL test_theme_inject: $1"; exit 1; }
echo "$out" | grep -q ':root{' || fail "no :root block"
echo "$out" | grep -q -- '--bg:#[0-9A-Fa-f]\{6\}' || fail "dark bg missing"
echo "$out" | grep -q ':root\[data-theme="light"\]{' || fail "light block missing"
echo "$out" | sed -n '/data-theme="light"/p' | grep -q -- '--acc:#[0-9A-Fa-f]\{6\}' || fail "light accent missing"
echo "$out" | grep -q -- '--mono:"Geist Mono"' || fail "mono font missing"
echo "PASS test_theme_inject"
