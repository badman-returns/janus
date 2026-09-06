#!/usr/bin/env bash
# autoresearch for Janus. One change per round on its own branch; a fixed eval decides keep or
# revert; a log the operator reads in the morning; nothing merges. The instructions the agent follows
# live in foundry/program.md — edit that, not this.
# Runs in the main checkout (~/code/janus), never a linked worktree — those
# are build checkouts sitting on somebody's branch.
# Usage: foundry-loop.sh [--rounds N] [--eval CMD] [--until HH:MM] [--dry]
# Env: FOUNDRY_AGENT — command that makes the change (default: headless Claude on the Janus account)
#      FOUNDRY_ALLOW_WORKTREE=1 — run in a linked worktree anyway
set -uo pipefail
source "$(dirname "$0")/job-guard.sh" 2>/dev/null || true
ROUNDS=6; EVAL="bash plugin/tests/run.sh"; UNTIL=""; DRY=0
while [ $# -gt 0 ]; do case "$1" in --rounds) ROUNDS=$2; shift 2;; --eval) EVAL=$2; shift 2;; --until) UNTIL=$2; shift 2;; --dry) DRY=1; shift;; *) shift;; esac; done
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "run inside the repo" >&2; exit 1; }
# A linked worktree is a build checkout parked on someone's branch — switching it to the default
# branch would yank that build out from under them. Resolve both paths: from a subdirectory git
# prints one absolute and one relative, and a bare string compare would refuse a good repo.
gitdir(){ (cd "$(git rev-parse "$1")" && pwd -P); }
[ "$(gitdir --git-dir)" = "$(gitdir --git-common-dir)" ] || [ "${FOUNDRY_ALLOW_WORKTREE:-}" = 1 ] \
  || { echo "linked worktree — refusing (FOUNDRY_ALLOW_WORKTREE=1 overrides)" >&2; exit 1; }
# Tracked work-in-progress must not ride onto a foundry branch. Untracked files are nobody's edit
# in progress, and foundry/ is the loop's own scratch (log.md, agent.log, the operator's program.md).
[ -z "$(git status --porcelain -uno -- ':!foundry')" ] || { echo "dirty tree — refusing" >&2; exit 1; }
for b in main master; do git show-ref -q --verify "refs/heads/$b" && { MAIN=$b; break; }; done
[ -n "${MAIN:-}" ] || { echo "no main or master branch — refusing" >&2; exit 1; }
git switch -q "$MAIN" || { echo "cannot switch to $MAIN — refusing" >&2; exit 1; }
mkdir -p foundry; touch foundry/log.md
AGENT=${FOUNDRY_AGENT:-"env CLAUDE_CONFIG_DIR=$HOME/.claude-tsg claude -p \"Read foundry/program.md and foundry/evidence.md. Make exactly ONE change it justifies, with a test under plugin/tests/, and commit it with a one-line message starting 'foundry:'. Do not touch main or merge.\""}
for n in $(seq 1 "$ROUNDS"); do
  [ -n "$UNTIL" ] && [ "$(date +%H:%M)" \> "$UNTIL" ] && [ "$(date +%H)" -lt 12 ] && { echo "stop: past $UNTIL"; break; }
  B="foundry/$(date +%F)-$n"
  # a name already taken (a kept branch from an earlier run today) must never fall through to a
  # round that commits on $MAIN — skip the round instead.
  git switch -q -c "$B" "$MAIN" 2>/dev/null || { echo "## [$(date +%F)] round $n | reverted | $B | branch already exists" >> foundry/log.md; continue; }
  [ $DRY = 1 ] && { echo "dry round $n on $B"; git switch -q "$MAIN"; git branch -q -D "$B"; continue; }
  bash -c "$AGENT" >> foundry/agent.log 2>&1 || true
  git checkout -q -- .   # only commits count; uncommitted leftovers must not ride back to $MAIN
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "$MAIN")" ]; then
    git switch -q "$MAIN"; git branch -q -D "$B"; echo "## [$(date +%F)] round $n | reverted | $B | agent made no commit" >> foundry/log.md; continue
  fi
  if bash -c "$EVAL" >> foundry/agent.log 2>&1; then
    MSG=$(git log -1 --format=%s); git switch -q "$MAIN"
    echo "## [$(date +%F)] round $n | kept | $B | $MSG" >> foundry/log.md
  else
    git switch -q "$MAIN"; git branch -q -D "$B"
    echo "## [$(date +%F)] round $n | reverted | $B | eval failed" >> foundry/log.md
  fi
done
git add foundry/log.md >/dev/null 2>&1 || true
tail -"$ROUNDS" foundry/log.md
