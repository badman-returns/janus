#!/usr/bin/env bash
# Which mission-control does this janus plugin drive? Prints the directory, or nothing.
#
# The cockpit and the agent layer are separate plugins sharing one file protocol, so a cockpit
# from another release renders an older protocol and looks exactly like the feature never shipped.
# That is not hypothetical: the old rule globbed every config dir and took `sort -V | tail -1`,
# which sorts whole PATHS — so `.claude-tsg` beat `.claude-apm` alphabetically whatever the
# versions were, and a freshly installed 0.9.0 silently lost to another account's stale 0.8.0.
#
# Hence the order: an explicit override, then the sibling of THIS plugin (same marketplace cache,
# same version — the only deterministic answer), then a repo checkout, then the newest in this
# cache, and only then anything on the box.
# Usage: mc-find.sh <plugin-root>
set -uo pipefail
ROOT=${1:?plugin root}

# A project can decline the cockpit entirely: `"cockpit": false`. Uninstalling the plugin is not
# enough on its own, because discovery reaches into other Claude config dirs and would find someone
# else's copy — so the machine would start a dashboard the operator had deliberately removed.
[ "$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('cockpit', True))" 2>/dev/null)" = False ] && exit 0

# Neither the marketplace nor this plugin's own name is hardcoded: a cache path is
# <cache>/<marketplace>/<plugin>/<version>, so the sibling is reachable by shape alone.
# Naming either one here would make a rename silently stop finding the cockpit.
SIBLING=""
case "$ROOT" in
  */plugins/cache/*/*/*) SIBLING="$ROOT/../../mission-control/$(basename "$ROOT")/mission-control" ;;
esac
CACHE=$(echo "$ROOT" | sed -n 's|\(.*/plugins/cache\)/.*|\1|p')

for c in "${DM_MISSION_CONTROL:-}" "$SIBLING" "$ROOT/../plugin-mc/mission-control" \
         $( [ -n "$CACHE" ] && ls -d "$CACHE"/*/mission-control/*/mission-control 2>/dev/null | sort -V | tail -1) \
         $(ls -d "$HOME"/.claude*/plugins/cache/*/mission-control/*/mission-control 2>/dev/null | sort -V | tail -1); do
  [ -n "$c" ] && [ -f "$c/server.js" ] && { (cd "$c" && pwd); exit 0; }
done
exit 0
