#!/usr/bin/env bash
# Remove worktrees under .claude/worktrees/ whose branch is fully merged into
# the default branch and whose tree is clean. Branches are never deleted.
# Usage: dm-prune.sh [--dry-run]   (from the project root)
set -uo pipefail
DRY=${1:-}
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
DEF=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); DEF=${DEF#origin/}
[ -n "$DEF" ] || for b in main master; do git show-ref -q --verify "refs/heads/$b" && { DEF=$b; break; }; done
[ -n "$DEF" ] || exit 0
git worktree list --porcelain | awk '/^worktree /{w=substr($0,10)} /^branch /{print w "\t" substr($0,8)}' |
while IFS=$'\t' read -r wt ref; do
  case "$wt" in "$ROOT"/.claude/worktrees/*) ;; *) continue ;; esac
  br=${ref#refs/heads/}
  if ! git merge-base --is-ancestor "$ref" "$DEF" 2>/dev/null; then echo "kept $wt ($br, unmerged)"; continue; fi
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then echo "kept $wt ($br, dirty)"; continue; fi
  if [ "$DRY" = --dry-run ]; then echo "would prune $wt ($br, merged)"
  else git worktree remove "$wt" && echo "pruned $wt ($br, merged)"; fi
done
exit 0
