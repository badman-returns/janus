#!/usr/bin/env bash
# The cockpit must match the agent layer's release. Written after a live failure: the old rule
# globbed every config dir and took `sort -V | tail -1`, which sorts whole PATHS — so a second
# account's `.claude-tsg` beat `.claude-apm` alphabetically whatever the versions were, and a
# freshly installed 0.9.0 served another account's stale 0.8.0. The page returned 200 and 404'd
# every asset, which reads as "the refactor did not ship".
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; F="$HERE/../scripts/mc-find.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL test_mc_find: $1"; exit 1; }

mc(){ mkdir -p "$1"; echo '//' > "$1/server.js"; }   # a plausible cockpit at $1

# two accounts, same marketplace. `apm` sorts BEFORE `tsg`, and holds the NEWER version —
# which is exactly the case the old glob got wrong.
APM="$T/.claude-apm/plugins/cache/janus-marketplace"
TSG="$T/.claude-tsg/plugins/cache/janus-marketplace"
mc "$APM/mission-control/0.9.0/mission-control"
mc "$TSG/mission-control/0.8.0/mission-control"
ROOT="$APM/janus/0.9.0"; mkdir -p "$ROOT/scripts"

got=$(HOME="$T" bash "$F" "$ROOT")
[ "$got" = "$APM/mission-control/0.9.0/mission-control" ] \
  || fail "picked the wrong account/version: $got"

# the version must match the plugin's own, not merely be the highest in the cache
mc "$APM/mission-control/1.2.0/mission-control"
got=$(HOME="$T" bash "$F" "$ROOT")
[ "$got" = "$APM/mission-control/0.9.0/mission-control" ] \
  || fail "took a newer sibling over its own version: $got"

# no sibling at this version -> fall back rather than serve nothing
ROOT2="$APM/janus/2.0.0"; mkdir -p "$ROOT2/scripts"
got=$(HOME="$T" bash "$F" "$ROOT2")
[ "$got" = "$APM/mission-control/1.2.0/mission-control" ] \
  || fail "no exact sibling should fall back to newest in the same cache, got: $got"

# an explicit override beats everything
got=$(HOME="$T" DM_MISSION_CONTROL="$TSG/mission-control/0.8.0/mission-control" bash "$F" "$ROOT")
[ "$got" = "$TSG/mission-control/0.8.0/mission-control" ] || fail "override ignored: $got"

# a repo checkout beside the plugin wins over any cache
REPO="$T/repo/plugin"; mkdir -p "$REPO/scripts"; mc "$T/repo/plugin-mc/mission-control"
got=$(HOME="$T" bash "$F" "$REPO")
[ "$got" = "$T/repo/plugin-mc/mission-control" ] || fail "repo checkout not preferred: $got"

# absent everywhere -> empty, exit 0 (the cockpit is optional; the machine still runs)
BARE="$T/bare/plugin"; mkdir -p "$BARE/scripts"
got=$(HOME="$T/nothing" bash "$BARE/../../.." 2>/dev/null; HOME="$T/nothing" bash "$F" "$BARE")
[ -z "$got" ] || fail "expected no cockpit, got: $got"

echo "PASS test_mc_find"
