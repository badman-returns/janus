#!/usr/bin/env bash
# autoresearch for Janus. One change per round, each on its own branch built in its own throwaway
# worktree under ~/.brain/foundry; a fixed eval decides keep or revert; a log the operator reads in
# the morning; nothing merges. The operator's checkout is never switched, never checked out, never
# stashed — the loop only reads its refs and appends to foundry/log.md.
# The instructions the agent follows live in foundry/program.md — edit that, not this.
# Usage: foundry-loop.sh [--rounds N] [--eval CMD] [--until HH:MM] [--agent CMD] [--dry]
# Env: FOUNDRY_AGENT — command that makes the change (default: headless Claude on the Janus account)
#      FOUNDRY_WT    — the round's worktree path (default ~/.brain/foundry/wt)
#      FOUNDRY_ALLOW_WORKTREE=1 — run from a linked worktree anyway
set -uo pipefail
source "$(dirname "$0")/job-guard.sh" 2>/dev/null || true
USAGE="usage: foundry-loop.sh [--rounds N] [--eval CMD] [--until HH:MM] [--agent CMD] [--dry]"
ROUNDS=6; EVAL="bash plugin/tests/run.sh"; UNTIL=""; DRY=0; AGENT=""
while [ $# -gt 0 ]; do case "$1" in
  --rounds|--eval|--until|--agent)
    [ $# -ge 2 ] || { echo "$1 needs a value" >&2; echo "$USAGE" >&2; exit 2; }
    case "$1" in --rounds) ROUNDS=$2;; --eval) EVAL=$2;; --until) UNTIL=$2;; --agent) AGENT=$2;; esac; shift 2;;
  --dry) DRY=1; shift;;
  *) echo "unknown flag: $1" >&2; echo "$USAGE" >&2; exit 2;;
esac; done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "run inside the repo" >&2; exit 1; }
# A linked worktree is a build checkout parked on someone's branch. The foundry reads the main
# checkout's refs and hangs its own worktrees off it. Resolve both paths: from a subdirectory git
# prints one absolute and one relative, and a bare string compare would refuse a good repo.
gitdir(){ (cd "$(git rev-parse "$1")" && pwd -P); }
[ "$(gitdir --git-dir)" = "$(gitdir --git-common-dir)" ] || [ "${FOUNDRY_ALLOW_WORKTREE:-}" = 1 ] \
  || { echo "cwd is a linked worktree, not the main checkout — refusing (FOUNDRY_ALLOW_WORKTREE=1 overrides)" >&2; exit 1; }
MAIN=$(git rev-parse --show-toplevel)          # every path below hangs off this, never off cwd
WT=${FOUNDRY_WT:-$HOME/.brain/foundry/wt}
# compared as real paths: MAIN comes back from git resolved, a FOUNDRY_WT may be spelled through a symlink
WTR=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$WT") && [ -n "$WTR" ] \
  || { echo "cannot resolve FOUNDRY_WT '$WT' (python3 missing?) — refusing rather than guessing where rm -rf points" >&2; exit 2; }
case "$WTR" in "$MAIN"|"$MAIN"/*) echo "FOUNDRY_WT must be a path outside the main checkout, got '$WT'" >&2; exit 2;; esac
LOG="$MAIN/foundry/log.md"; ALOG="$MAIN/foundry/agent.log"
# Branches are read from MAIN's refs, not its HEAD: the operator may be on a feature branch or
# detached, and the foundry still builds from the default branch.
for b in main master; do git -C "$MAIN" show-ref -q --verify "refs/heads/$b" && { BASE=$b; break; }; done
[ -n "${BASE:-}" ] || { echo "no main or master branch — refusing" >&2; exit 1; }
[ -n "$AGENT" ] || AGENT=${FOUNDRY_AGENT:-"env CLAUDE_CONFIG_DIR=$HOME/.claude-tsg claude -p \"Read foundry/program.md and foundry/evidence.md. Make exactly ONE change it justifies, with a test under plugin/tests/, and commit it with a one-line message starting 'foundry:'. Do not touch $BASE, do not merge.\""}
# --until HH:MM is a clock time: today's if still ahead, else tomorrow's (the night job starts at
# 03:00 and stops at 06:30; a hand run in the afternoon with the same flag runs until tomorrow 06:30).
DEADLINE=""
if [ -n "$UNTIL" ]; then
  DEADLINE=$(python3 -c '
import datetime as d, sys
h, m = (int(x) for x in sys.argv[1].split(":")); n = d.datetime.now()
t = n.replace(hour=h, minute=m, second=0, microsecond=0)
if t <= n: t += d.timedelta(days=1)
print(int(t.timestamp()))' "$UNTIL" 2>/dev/null) || { echo "--until wants HH:MM, got '$UNTIL'" >&2; echo "$USAGE" >&2; exit 2; }
fi
mkdir -p "$MAIN/foundry"; touch "$LOG"

one(){ tr '\n' ' ' | tr '|' '/' | cut -c1-200 | sed 's/ *$//'; }   # a log line has | fields; keep them
say(){ echo "## [$(date +%F)] round $1 | $2 | $3 | $4" >> "$LOG"; }
die(){ echo "## [$(date +%F)] $1" >> "$LOG"; echo "$1" >&2; exit 1; }
# no `worktree prune`: it is repo-wide and would unregister an operator's own worktree whose
# directory happens to be away; `remove --force` clears a stale registration of $WT on its own
wt_clear(){ git -C "$MAIN" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$WT"; mkdir -p "$(dirname "$WT")"; }
wt_add(){ wt_clear; git -C "$MAIN" worktree add -q "$WT" -b "$1" "$BASE" 2>&1; }  # stderr is the return value
wt_add_detached(){ wt_clear; git -C "$MAIN" worktree add -q --detach "$WT" "$BASE" 2>&1; }  # the baseline needs no branch
wt_drop(){ ERR=$(git -C "$MAIN" worktree remove --force "$WT" 2>&1) \
  || die "worktree $WT could not be removed, branch state unknown: $(printf %s "$ERR" | one)"; }
drop_branch(){ ERR=$(git -C "$MAIN" branch -q -D "$1" 2>&1) \
  || die "branch $1 could not be deleted after its worktree went away: $(printf %s "$ERR" | one)"; }

# Nothing to read means nothing to do. program.md reaches the default branch only when the branch
# carrying it merges; until then the night job says so and stops instead of inventing work.
git -C "$MAIN" cat-file -e "$BASE:foundry/program.md" 2>/dev/null \
  || { echo "## [$(date +%F)] no foundry/program.md on $BASE" >> "$LOG"; tail -1 "$LOG"; exit 0; }
# evidence.md is the round's other input — what actually went wrong yesterday. The round is built in
# a checkout of $BASE, so the agent can only read it if it is there; without it the loop would invent
# work six times a night from nothing.
git -C "$MAIN" cat-file -e "$BASE:foundry/evidence.md" 2>/dev/null \
  || { echo "## [$(date +%F)] no foundry/evidence.md on $BASE" >> "$LOG"; tail -1 "$LOG"; exit 0; }

# The eval on an untouched checkout of the default branch. A red baseline would score six rounds
# "reverted" for a breakage none of them caused, so it stops the night instead.
if [ $DRY = 0 ]; then
  ERR=$(wt_add_detached) || die "baseline worktree failed: $(printf %s "$ERR" | one)"
  if ! ( cd "$WT" && bash -c "$EVAL" ) >> "$ALOG" 2>&1; then
    echo "## [$(date +%F)] baseline red on $BASE: $(tail -1 "$ALOG" | one)" >> "$LOG"
    wt_drop; tail -1 "$LOG"; exit 1
  fi
  wt_drop
fi

for n in $(seq 1 "$ROUNDS"); do
  [ -n "$DEADLINE" ] && [ "$(date +%s)" -ge "$DEADLINE" ] && { echo "stop: past $UNTIL"; break; }
  BR="foundry/$(date +%F)-$n"
  ERR=$(wt_add "$BR") || { say "$n" reverted "$BR" "worktree add failed: $(printf %s "$ERR" | one)"; continue; }
  START=$(git -C "$WT" rev-parse HEAD)          # the round's own start, not a live ref the operator may move
  [ $DRY = 1 ] && { echo "dry round $n on $BR"; wt_drop; drop_branch "$BR"; continue; }
  if ! ( cd "$WT" && bash -c "$AGENT" ) >> "$ALOG" 2>&1; then
    say "$n" reverted "$BR" "agent failed: $(tail -1 "$ALOG" | one)"; wt_drop; drop_branch "$BR"; continue
  fi
  if [ "$(git -C "$WT" rev-parse HEAD)" = "$START" ]; then
    say "$n" reverted "$BR" "agent made no commit"; wt_drop; drop_branch "$BR"; continue
  fi
  if ( cd "$WT" && bash -c "$EVAL" ) >> "$ALOG" 2>&1; then
    MSG=$(git -C "$WT" log -1 --format=%s | one); wt_drop      # the branch stays for the morning
    say "$n" kept "$BR" "$MSG"
  else
    say "$n" reverted "$BR" "eval failed: $(tail -1 "$ALOG" | one)"; wt_drop; drop_branch "$BR"
  fi
done
tail -"$ROUNDS" "$LOG"
