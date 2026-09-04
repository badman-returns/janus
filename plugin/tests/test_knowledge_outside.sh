#!/usr/bin/env bash
# The KNOWLEDGE band badges a path "outside repo" to mean "no git repo tracks this, so this log is
# its only trace". Written after the first live run badged `../programs/arc/atlas/specs/P6.yaml`
# that way: it is above the project root, but it is fully versioned in the parent repo. Telling the
# operator a tracked file has no trace is worse than not showing the band at all.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SRV="$HERE/../../plugin-mc/mission-control/server.js"
T=$(mktemp -d); PORT=5593; PID=""
trap '[ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_knowledge_outside: $1"; exit 1; }

# a repo, with the project in a subdirectory of it — the shape that got this wrong
mkdir -p "$T/outer/proj/.delivery" "$T/nogit"
git -C "$T/outer" init -q 2>/dev/null || fail "git init"
echo "versioned" > "$T/outer/tracked.md"
echo "loose"     > "$T/nogit/note.md"
echo '{"project":"t"}' > "$T/outer/proj/.delivery/config.json"

K="$T/outer/proj/.delivery/knowledge.log"
printf '2026-09-04T10:00:00Z\t../tracked.md\twrite\n'      >> "$K"   # above the root, but IN the repo
printf '2026-09-04T10:01:00Z\t%s/note.md\twrite\n' "$T/nogit" >> "$K" # absolute, in no repo
printf '2026-09-04T10:02:00Z\t.delivery/config.json\tedit\n' >> "$K" # plainly inside

node "$SRV" --port $PORT --project "$T/outer/proj" --session dm-none >/dev/null 2>&1 & PID=$!; disown
for i in $(seq 1 40); do curl -sf "localhost:$PORT/api/state" >/dev/null && break; sleep 0.25; done
curl -sf "localhost:$PORT/api/state" > "$T/state.json" || fail "server did not come up"

python3 - "$T/state.json" "$T/nogit" <<'EOF' || exit 1
import json, sys
s = json.load(open(sys.argv[1])); nogit = sys.argv[2]
by = {p["path"]: p for p in s["knowledge"]["paths"]}
def die(m): print("FAIL test_knowledge_outside: " + m); sys.exit(1)

if s["knowledge"]["writes"] != 3: die(f"expected 3 writes, got {s['knowledge']['writes']}")

t = by.get("../tracked.md") or die("../tracked.md missing from the grouping")
if t["outside"]: die("a file above the project root but tracked by the parent repo was badged 'outside' — the bug this test exists for")

c = by.get(".delivery/config.json") or die(".delivery/config.json missing")
if c["outside"]: die("a plainly in-repo path was badged outside")

n = by.get(nogit + "/note.md") or die("the untracked absolute path missing")
if not n["outside"]: die("a path no repo tracks was NOT badged outside — the badge would then mean nothing")

print("ok")
EOF

echo "PASS test_knowledge_outside"
