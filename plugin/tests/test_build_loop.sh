#!/usr/bin/env bash
# build-loop.sh: runs the open tasks of a plan through a stub headless claude, skips a task whose
# dependency is still open, marks a blocked task, waits out a usage limit and retries, checks boxes
# as tasks report DONE, and works on the build branch, never main.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; BL="$HERE/../scripts/build-loop.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_build_loop: $1"; exit 1; }
cd "$T" && git init -q && git commit -q --allow-empty -m init && mkdir -p .delivery bin
cat > plan.md <<'EOF'
# Plan
### Task 0: Operator thing
**Depends on:** none
- [ ] **Step 1: ask the operator.**
### Task 1: Independent
**Depends on:** none
- [ ] **Step 1: make a.**
- [ ] **Step 2: make b.**
### Task 2: Needs zero
**Depends on:** Task 0
- [ ] **Step 1: after zero.**
EOF
cat > bin/claude <<'EOF'
#!/usr/bin/env bash
P="$2"; N=$(printf '%s' "$P" | grep -oE 'Task [0-9]+' | head -1 | grep -oE '[0-9]+'); PLAN=$(printf '%s' "$P" | grep -oE 'plan at [^ ,]+' | head -1 | sed 's/plan at //')
if [ ! -f .limit-seen ]; then touch .limit-seen; echo "Claude usage limit reached. Your limit resets at 99:99."; exit 1; fi
python3 - "$PLAN" "$N" <<'PY'
import re,sys
p,n=sys.argv[1],sys.argv[2]; t=open(p).read()
parts=re.split(r'(^### Task \d+: .*$)', t, flags=re.M)
for i in range(1,len(parts),2):
    if parts[i].startswith(f'### Task {n}:'):
        parts[i+1]=parts[i+1].replace('- [ ]', '- [?]' if n=='0' else '- [x]', 1)
open(p,'w').write(''.join(parts))
print('BLOCKED 0 need the operator' if n=='0' else f'DONE {n} stub')
PY
EOF
chmod +x bin/claude
export CLAUDE_BIN="$T/bin/claude" BUILD_LIMIT_WAIT=1 BUILD_SLEEP=1
bash "$BL" --once plan.md >/dev/null 2>&1 || fail "first pass exited $?"
grep -q '^- \[?\] \*\*Step 1: ask' plan.md || fail "task 0 not marked blocked"
[ "$(grep -c '^- \[x\]' plan.md)" = 1 ] || fail "task 1 should have one box checked after one pass, has $(grep -c '^- \[x\]' plan.md)"
grep -q '^- \[ \] \*\*Step 1: after zero' plan.md || fail "task 2 ran although task 0 is open"
grep -q 'usage limit' .delivery/build.log || fail "limit not logged"
[ "$(git rev-parse --abbrev-ref HEAD)" = front-door ] || fail "not on the front-door branch"
bash "$BL" --once plan.md >/dev/null 2>&1
[ "$(grep -c '^- \[x\]' plan.md)" = 2 ] || fail "task 1 not finished on the second pass"
echo "PASS test_build_loop"
