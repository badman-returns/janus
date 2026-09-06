#!/usr/bin/env bash
# foundry-loop.sh: a round whose eval fails leaves main untouched and no branch behind; a passing round
# keeps its branch, never merges. The "agent" is a stub that makes one commit.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; FL="$HERE/../scripts/foundry-loop.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_foundry_round: $1"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
cd "$T"; git init -q -b main; mkdir -p foundry; echo "# program" > foundry/program.md; echo base > f; git add -A; git commit -qm base; BASE=$(git rev-parse HEAD)
printf '#!/usr/bin/env bash\necho change >> f; git add f; git commit -qm "foundry: change"\n' > agent.sh; chmod +x agent.sh
FOUNDRY_AGENT="$T/agent.sh" bash "$FL" --rounds 1 --eval false || fail "loop exited $? on a failing eval"
[ "$(git rev-parse HEAD)" = "$BASE" ] || fail "main moved after a failed round"
[ "$(git branch --list 'foundry/*' | wc -l | tr -d ' ')" = 0 ] || fail "failed round left a branch"
grep -q '| reverted |' foundry/log.md || fail "revert not logged: $(cat foundry/log.md)"
FOUNDRY_AGENT="$T/agent.sh" bash "$FL" --rounds 1 --eval true || fail "loop exited $? on a passing eval"
[ "$(git rev-parse HEAD)" = "$BASE" ] || fail "main moved after a passing round (merged?)"
[ "$(git branch --list 'foundry/*' | wc -l | tr -d ' ')" = 1 ] || fail "passing round did not keep exactly one branch"
grep -q '| kept |' foundry/log.md || fail "kept not logged"
echo "PASS test_foundry_round"
