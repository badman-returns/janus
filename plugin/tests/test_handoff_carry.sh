#!/usr/bin/env bash
# The handoff has to carry the two things a fresh session cannot reconstruct: the open checklist
# (what was being done, and what would prove each item) and the knowledge trail (three of the four
# knowledge locations are in git, but a write to a memory directory outside any repo leaves
# knowledge.log as its only trace). Written because the /dm skill promised the checklist was in the
# handoff before anything put it there.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; H="$HERE/../scripts/handoff.sh"; S="$HERE/../scripts/session-start.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL test_handoff_carry: $1"; exit 1; }

cd "$T" || fail "cd"
mkdir -p .delivery/inbox .delivery/checklist
echo '{"project":"t"}' > .delivery/config.json

# one unfinished slice, one fully finished slice (the finished one must NOT appear as a resume point)
cat > .delivery/checklist/wiring.json <<'EOF'
{"slice":"wiring","intent":"wire the invite endpoint","gated":true,"triggers":["files>4"],
 "approved_at":null,
 "items":[{"text":"read the payload","proof":"schema printed","done":true,"ts":"2026-09-04T00:00:00Z"},
          {"text":"drive the flow","proof":"screenshot in proof/","done":false,"ts":null}]}
EOF
cat > .delivery/checklist/finished.json <<'EOF'
{"slice":"finished","intent":"done already","gated":false,"triggers":[],"approved_at":null,
 "items":[{"text":"a","proof":"b","done":true,"ts":"2026-09-04T00:00:00Z"}]}
EOF
printf '2026-09-04T10:00:00Z\tprograms/arc/atlas/specs/P6.yaml\twrite\n' >> .delivery/knowledge.log
printf '2026-09-04T10:05:00Z\tprograms/arc/atlas/specs/P6.yaml\tedit\n'  >> .delivery/knowledge.log
printf '2026-09-04T10:09:00Z\t/Users/x/.claude-apm/projects/p/memory/note.md\twrite\n' >> .delivery/knowledge.log

bash "$H" || fail "handoff.sh exited nonzero"
[ -s .delivery/HANDOFF.md ] || fail "no HANDOFF.md written"
HO=$(cat .delivery/HANDOFF.md)

# the open slice, its intent, its unchecked item AND that item's proof
echo "$HO" | grep -q "wiring"                    || fail "open slice missing"
echo "$HO" | grep -q "wire the invite endpoint"  || fail "intent missing"
echo "$HO" | grep -q "drive the flow"            || fail "unchecked item missing"
echo "$HO" | grep -q "screenshot in proof/"      || fail "the item's proof method missing — the point of carrying it"
echo "$HO" | grep -q "NOT YET"                   || fail "gated-but-unapproved not flagged"
# a finished checklist is not a resume point
echo "$HO" | grep -q "done already"              && fail "a fully-checked slice was carried as open work"

# knowledge, grouped, with the out-of-repo write present
echo "$HO" | grep -q "P6.yaml"                   || fail "knowledge path missing"
echo "$HO" | grep -q "2 edits"                   || fail "repeat edits not counted"
echo "$HO" | grep -q "memory/note.md"            || fail "out-of-repo memory write missing — its only trace"

# and session start names the resume point rather than leaving it to be discovered
OUT=$(bash "$S" 2>/dev/null)
echo "$OUT" | grep -q "OPEN CHECKLIST: wiring" || fail "session-start did not surface the open checklist"
echo "$OUT" | grep -q "1/2 done"               || fail "session-start did not say how far along"
echo "$OUT" | grep -q "GATED, NOT APPROVED"    || fail "session-start did not flag the unapproved gate"
# match the announcement, not the word: the handoff heading says "unfinished work", and
# session-start cats the handoff, so a bare grep for "finished" hits that instead.
echo "$OUT" | grep -q "OPEN CHECKLIST: finished" && fail "session-start surfaced a finished slice as open"

# empty project: both must stay quiet rather than inventing sections
rm -rf .delivery/checklist .delivery/knowledge.log
bash "$H" || fail "handoff.sh nonzero with nothing to carry"
grep -q "none open"        .delivery/HANDOFF.md || fail "no empty-state for checklists"
grep -q "none this session" .delivery/HANDOFF.md || fail "no empty-state for knowledge"

echo "PASS test_handoff_carry"
