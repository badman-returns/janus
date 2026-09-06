#!/usr/bin/env bash
# foundry-loop.sh: a round whose eval fails leaves the default branch untouched and no branch behind;
# a passing round keeps its branch, never merges. The whole story runs twice — once on a repo whose
# default branch is main, once on master, since the loop detects which. And it must refuse to run
# inside a linked worktree, which is somebody's build checkout. The "agent" is a stub that commits.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; FL="$HERE/../scripts/foundry-loop.sh"
TOP=$(mktemp -d); trap 'rm -rf "$TOP"' EXIT; fail(){ echo "FAIL test_foundry_round: $1"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

story(){ # $1 = the repo's default branch name
  T="$TOP/$1"; mkdir -p "$T"; cd "$T"
  git init -q -b "$1"; mkdir -p foundry; echo "# program" > foundry/program.md; echo base > f; git add -A; git commit -qm base; BASE=$(git rev-parse HEAD)
  printf '#!/usr/bin/env bash\necho change >> f; git add f; git commit -qm "foundry: change"\n' > agent.sh; chmod +x agent.sh
  FOUNDRY_AGENT="$T/agent.sh" bash "$FL" --rounds 1 --eval false || fail "[$1] loop exited $? on a failing eval"
  [ "$(git rev-parse HEAD)" = "$BASE" ] || fail "[$1] default branch moved after a failed round"
  [ "$(git branch --list 'foundry/*' | wc -l | tr -d ' ')" = 0 ] || fail "[$1] failed round left a branch"
  grep -q '| reverted |' foundry/log.md || fail "[$1] revert not logged: $(cat foundry/log.md)"
  FOUNDRY_AGENT="$T/agent.sh" bash "$FL" --rounds 1 --eval true || fail "[$1] loop exited $? on a passing eval"
  [ "$(git rev-parse HEAD)" = "$BASE" ] || fail "[$1] default branch moved after a passing round (merged?)"
  [ "$(git branch --list 'foundry/*' | wc -l | tr -d ' ')" = 1 ] || fail "[$1] passing round did not keep exactly one branch"
  grep -q '| kept |' foundry/log.md || fail "[$1] kept not logged"
  [ "$(git branch --show-current)" = "$1" ] || fail "[$1] loop parked on $(git branch --show-current)"
}
story main
story master

cd "$TOP/main"; git worktree add -q "$TOP/wt" -b build-branch
( cd "$TOP/wt" && bash "$FL" --rounds 1 --dry ) 2>/dev/null && fail "ran inside a linked worktree"
[ "$(git -C "$TOP/wt" branch --show-current)" = build-branch ] || fail "worktree left its branch"
echo "PASS test_foundry_round"
