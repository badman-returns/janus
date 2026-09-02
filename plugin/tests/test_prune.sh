#!/usr/bin/env bash
# dm-prune.sh: merged + clean worktree removed; unmerged or dirty kept; branches never deleted.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/dm-prune.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"; fail(){ echo "FAIL test_prune: $1"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q -b main && echo a > a && git add a && git commit -qm base
W=.claude/worktrees
git worktree add -q "$W/merged" -b merged && echo m > "$W/merged/m" && git -C "$W/merged" add m && git -C "$W/merged" commit -qm merged
git worktree add -q "$W/open" -b open && echo o > "$W/open/o" && git -C "$W/open" add o && git -C "$W/open" commit -qm open
git worktree add -q "$W/dirty" -b dirty && echo junk > "$W/dirty/junk"
git merge -q --ff-only merged && git merge -q --no-ff -m x dirty   # dirty's branch is merged, its tree is not clean

out=$(bash "$S" --dry-run) || fail "dry-run exit $?"
[ -d "$W/merged" ] || fail "dry-run removed a worktree"
echo "$out" | grep -q "would prune .*/merged (merged, merged)" || fail "dry-run output: $out"

out=$(bash "$S") || fail "prune exit $?"
echo "$out" | grep -q "^pruned .*/merged (merged, merged)$" || fail "pruned line missing: $out"
echo "$out" | grep -q "^kept .*/open (open, unmerged)$" || fail "unmerged kept line missing: $out"
echo "$out" | grep -q "^kept .*/dirty (dirty, dirty)$" || fail "dirty kept line missing: $out"
[ ! -d "$W/merged" ] || fail "merged worktree still on disk"
[ -d "$W/open" ] || fail "unmerged worktree removed"
[ -d "$W/dirty" ] || fail "dirty worktree removed"
git worktree list | grep -q "/merged " && fail "merged worktree still registered"
for b in merged open dirty; do git show-ref -q --verify "refs/heads/$b" || fail "branch $b deleted"; done
echo "PASS test_prune"
