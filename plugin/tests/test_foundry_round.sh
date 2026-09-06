#!/usr/bin/env bash
# foundry-loop.sh must never touch the operator's checkout. Every round is built in its own
# throwaway worktree: a kept round leaves its branch behind, a reverted one leaves nothing, and the
# operator's work in progress — unstaged, staged, untracked — is byte-for-byte where he left it,
# on the branch he left it on. Also: a red baseline stops the night, a missing program.md stops it,
# a linked worktree is refused, and a flag without a value is a usage error.
# Stub agent, stub eval, temp HOME and temp FOUNDRY_WT — nothing here can reach the real repo.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; FL="$HERE/../scripts/foundry-loop.sh"
TOP=$(mktemp -d); trap 'rm -rf "$TOP"' EXIT; fail(){ echo "FAIL test_foundry_round: $1"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export HOME="$TOP/home"; mkdir -p "$HOME"        # no test may reach the real ~/.brain
D=$(date +%F)

printf '#!/usr/bin/env bash\necho change >> f; git add f; git commit -qm "foundry: change"\n' > "$TOP/agent.sh"
# eval stub: passes while the call count is <= PASSES (call 1 is the baseline, then one per round)
printf '#!/usr/bin/env bash\nn=$(( $(cat "$COUNT" 2>/dev/null || echo 0) + 1 )); echo $n > "$COUNT"\necho "eval call $n"; [ "$n" -le "${PASSES:-2}" ]\n' > "$TOP/eval.sh"
chmod +x "$TOP/agent.sh" "$TOP/eval.sh"
run(){ WT=$1; shift; rc=0; FOUNDRY_WT="$WT" bash "$FL" --agent "$TOP/agent.sh" --eval "bash $TOP/eval.sh" "$@" > "$TOP/out" 2>&1 || rc=$?; }

# a repo mid-edit: one unstaged change, one staged change, one untracked file
setup(){ # $1 = dir  $2 = default branch
  mkdir -p "$1"; cd "$1"; git init -q -b "$2"
  mkdir foundry; echo "# program" > foundry/program.md
  printf 'foundry/log.md\n*.log\n' > .gitignore
  echo base > f; echo two > g; git add -A; git commit -qm base
  echo "operator was here" >> f; echo "staged" >> g; git add g; echo scratch > untracked
}

story(){ # $1 = the repo's default branch name
  local T="$TOP/$1"; setup "$T" "$1"
  local BASESHA; BASESHA=$(git rev-parse HEAD)
  cp f "$TOP/f.$1"; cp g "$TOP/g.$1"; cp untracked "$TOP/u.$1"
  local ST; ST=$(git status --porcelain)
  export COUNT="$TOP/count" PASSES=2; rm -f "$COUNT"     # baseline + round 1 pass, round 2 fails
  run "$TOP/wt" --rounds 2
  [ "$rc" = 0 ] || fail "[$1] loop exited $rc: $(cat "$TOP/out")"

  cmp -s f "$TOP/f.$1" || fail "[$1] the unstaged edit was lost"
  cmp -s g "$TOP/g.$1" || fail "[$1] the staged file changed on disk"
  cmp -s untracked "$TOP/u.$1" || fail "[$1] the untracked file changed"
  [ "$(git status --porcelain)" = "$ST" ] || fail "[$1] status changed: $(git status --porcelain)"
  [ "$(git rev-parse HEAD)" = "$BASESHA" ] || fail "[$1] HEAD moved"
  [ "$(git branch --show-current)" = "$1" ] || fail "[$1] checkout left its branch"
  [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ] || fail "[$1] a worktree was left behind: $(git worktree list)"
  [ "$(git rev-list --count "$BASESHA..foundry/$D-1")" = 1 ] || fail "[$1] kept branch is not one commit ahead of $1"
  git show-ref -q --verify "refs/heads/foundry/$D-2" && fail "[$1] the reverted branch still exists"
  sed -n 1p foundry/log.md | grep -q "round 1 | kept | foundry/$D-1 | foundry: change" || fail "[$1] line 1: $(cat foundry/log.md)"
  sed -n 2p foundry/log.md | grep -q "round 2 | reverted | foundry/$D-2 | eval failed" || fail "[$1] line 2: $(cat foundry/log.md)"

  rm -f "$COUNT"; run "$TOP/wt" --rounds 2            # a second night appends, never truncates
  [ "$rc" = 0 ] || fail "[$1] second run exited $rc: $(cat "$TOP/out")"
  [ "$(wc -l < foundry/log.md | tr -d ' ')" = 4 ] || fail "[$1] log is not four lines: $(cat foundry/log.md)"
  [ "$(git status --porcelain)" = "$ST" ] || fail "[$1] status changed on the second run"
}
story main
story master

# a red default branch stops the night before it scores rounds "reverted" for a breakage they did not cause
setup "$TOP/red" main
export COUNT="$TOP/count" PASSES=0; rm -f "$COUNT"
run "$TOP/wt-red" --rounds 2
[ "$rc" = 1 ] || fail "baseline red exited $rc, want 1: $(cat "$TOP/out")"
grep -q "baseline red on main" foundry/log.md || fail "no baseline line: $(cat foundry/log.md)"
[ "$(git branch --list 'foundry/*' | wc -l | tr -d ' ')" = 0 ] || fail "baseline left a branch"
[ "$(git worktree list | wc -l | tr -d ' ')" = 1 ] || fail "baseline left a worktree"

# nothing to read: program.md has not reached the default branch yet
setup "$TOP/noprog" main; git rm -q --cached foundry/program.md; git commit -qm "drop program"
export COUNT="$TOP/count" PASSES=9; rm -f "$COUNT"
run "$TOP/wt-np" --rounds 2
[ "$rc" = 0 ] || fail "missing program.md exited $rc: $(cat "$TOP/out")"
grep -q "no foundry/program.md on main" foundry/log.md || fail "missing program.md not logged: $(cat foundry/log.md)"
[ "$(git branch --list 'foundry/*' | wc -l | tr -d ' ')" = 0 ] || fail "missing program.md still cut a branch"

# a linked worktree is somebody's build checkout, and everything else here would have worked
setup "$TOP/ref" main; git worktree add -q "$TOP/linked" -b build-branch
export COUNT="$TOP/count" PASSES=9; rm -f "$COUNT"
cd "$TOP/linked"; run "$TOP/wt-ref" --rounds 1
[ "$rc" = 1 ] || fail "linked worktree not refused (exit $rc): $(cat "$TOP/out")"
grep -q "linked worktree" "$TOP/out" || fail "refusal did not say why: $(cat "$TOP/out")"
[ "$(git branch --list 'foundry/*' | wc -l | tr -d ' ')" = 0 ] || fail "refused run still cut a branch"
rc=0; FOUNDRY_ALLOW_WORKTREE=1 FOUNDRY_WT="$TOP/wt-ref" bash "$FL" --rounds 1 --dry > "$TOP/out" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "FOUNDRY_ALLOW_WORKTREE=1 did not run (exit $rc): $(cat "$TOP/out")"
grep -q "dry round 1" "$TOP/out" || fail "override never reached a round: $(cat "$TOP/out")"

# a flag without its value is a usage error, not a round
rc=0; bash "$FL" --eval > "$TOP/out" 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "--eval with no value exited $rc, want 2"
grep -q "usage:" "$TOP/out" || fail "no usage line: $(cat "$TOP/out")"
rc=0; bash "$FL" --nonsense > "$TOP/out" 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown flag exited $rc, want 2"

echo "PASS test_foundry_round"
