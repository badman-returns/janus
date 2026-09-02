#!/usr/bin/env bash
# Plugin identity stays coherent: every plugin.json name is a marketplace entry, both versions
# match, every documented install command names a plugin that exists, and cockpit discovery is
# not pinned to a marketplace name. Guards the rename path — a half-applied rename ships install
# commands for a plugin nobody can install.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
fail(){ echo "FAIL test_identity: $1"; exit 1; }
j(){ python3 -c "import json,sys;print(json.load(open('$1'))$2)"; }

MKT="$ROOT/.claude-plugin/marketplace.json"
[ -f "$MKT" ] || fail "no marketplace.json"

MKT_NAME=$(j "$MKT" "['name']")
NAMES=$(python3 -c "
import json;print(' '.join(p['name'] for p in json.load(open('$MKT'))['plugins']))")

# 1. every plugin.json name is listed in the marketplace, and its source points at itself
for p in plugin plugin-mc; do
  PJ="$ROOT/$p/.claude-plugin/plugin.json"
  [ -f "$PJ" ] || fail "$p has no plugin.json"
  N=$(j "$PJ" "['name']")
  echo " $NAMES " | grep -q " $N " || fail "plugin '$N' ($p) is not in $MKT_NAME"
  SRC=$(python3 -c "
import json
m=json.load(open('$MKT'))
print(next(x['source'] for x in m['plugins'] if x['name']=='$N'))")
  [ "$SRC" = "./$p" ] || fail "marketplace maps '$N' to $SRC, but it lives in ./$p"
done

# 2. both versions move together — the repo law is to bump both
VA=$(j "$ROOT/plugin/.claude-plugin/plugin.json" "['version']")
VB=$(j "$ROOT/plugin-mc/.claude-plugin/plugin.json" "['version']")
[ "$VA" = "$VB" ] || fail "versions diverged: plugin $VA, plugin-mc $VB"

# 3. every documented install command names a plugin that exists in this marketplace
while read -r ref; do
  [ -n "$ref" ] || continue
  pn=${ref%@*}; mn=${ref#*@}
  [ "$mn" = "$MKT_NAME" ] || fail "docs install from '$mn', marketplace is '$MKT_NAME' ($ref)"
  echo " $NAMES " | grep -q " $pn " || fail "docs install '$pn', which is not a plugin in $MKT_NAME"
done < <(grep -rhoE '[a-z0-9-]+@[a-z0-9-]+-marketplace' \
           "$ROOT/README.md" "$ROOT/GUIDE.md" "$ROOT/plugin" "$ROOT/plugin-mc" 2>/dev/null | sort -u)

# 4. cockpit discovery must not pin a marketplace name — renaming the marketplace would
#    silently stop finding an installed cockpit, with no error anywhere.
grep -q 'plugins/cache/\*/mission-control' "$ROOT/plugin/scripts/orchestrator.sh" \
  || fail "orchestrator cockpit discovery is pinned to a marketplace name"

echo "PASS test_identity"
