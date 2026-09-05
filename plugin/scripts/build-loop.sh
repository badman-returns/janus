#!/usr/bin/env bash
# build-loop.sh — executes implementation plans task by task with headless Claude, unattended.
# The plan file is the state: a step is `- [ ]` (open), `- [x]` (done) or `- [?]` (blocked on the
# operator). A task runs when it has open steps and every task on its `**Depends on:**` line has
# none. Each pass hands every runnable task, in file order, to one headless session that follows the
# task's own steps, runs the tests, checks the boxes and commits on the build branch. A usage limit
# is waited out and the task retried; a pass that makes no progress sleeps; the loop exits only when
# every box in every plan is checked. Restart it any time: nothing is lost, the boxes are the state.
# Usage: build-loop.sh [--branch NAME] [--model NAME] [--once] <plan.md> [<plan.md>...]
# Env: CLAUDE_BIN (default claude), BUILD_MODEL (default sonnet), BUILD_SLEEP (idle pass, default 1800),
#      BUILD_LIMIT_WAIT (when the reset time cannot be read, default 1200),
#      BUILD_PERMISSIONS (flags for the headless session; default lets it run unattended on this repo —
#      set "--permission-mode acceptEdits" to make every shell command a card the operator answers).
set -uo pipefail
BRANCH=front-door; MODEL=${BUILD_MODEL:-sonnet}; ONCE=0; PLANS=()
while [ $# -gt 0 ]; do case "$1" in
  --branch) BRANCH=$2; shift 2;; --model) MODEL=$2; shift 2;; --once) ONCE=1; shift;;
  *) PLANS+=("$1"); shift;; esac; done
[ ${#PLANS[@]} -gt 0 ] || { echo "usage: build-loop.sh [--branch NAME] [--model NAME] [--once] <plan.md>..."; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; CLAUDE=${CLAUDE_BIN:-claude}
command -v "$CLAUDE" >/dev/null 2>&1 || { echo "build-loop: $CLAUDE not found"; exit 1; }
PERMS=${BUILD_PERMISSIONS:---dangerously-skip-permissions}
mkdir -p .delivery/build; LOG=.delivery/build.log
log(){ echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
notify(){ bash "$HERE/notify.sh" "$1" 2>/dev/null || true; }
# the account: the machine's own, as watch.sh does; never main
CFG=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('claude_config_dir') or '')" 2>/dev/null || true)
[ -n "$CFG" ] && export CLAUDE_CONFIG_DIR="${CFG/#\~/$HOME}"
cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [ "$cur" != "$BRANCH" ]; then git checkout -q "$BRANCH" 2>/dev/null || git checkout -q -b "$BRANCH" || { log "cannot switch to $BRANCH"; exit 1; }; fi

# runnable tasks of a plan: "N<TAB>title" for every task with open steps whose dependencies are closed
runnable(){ python3 - "$1" <<'PY'
import re,sys
t=open(sys.argv[1],encoding='utf-8').read()
parts=re.split(r'^### Task (\d+): (.*)$', t, flags=re.M)
tasks={}; order=[]
for i in range(1,len(parts),3):
    n,title,body=parts[i],parts[i+1].strip(),parts[i+2]
    openness=bool(re.search(r'^- \[[ ?]\]', body, re.M))
    m=re.search(r'^\*\*Depends on:\*\*\s*(.*)$', body, re.M)
    deps=re.findall(r'\d+', m.group(1)) if m and 'none' not in m.group(1).lower() else []
    tasks[n]=(title,openness,deps); order.append(n)
for n in order:
    title,openness,deps=tasks[n]
    if openness and all(not tasks.get(d,('',False,[]))[1] for d in deps): print(f"{n}\t{title}")
PY
}
count_open(){ grep -cE '^- \[[ ?]\]' "$1" 2>/dev/null || echo 0; }
wait_secs(){ python3 - "$1" "${BUILD_LIMIT_WAIT:-1200}" <<'PY'
import sys,re,datetime
s,dflt=sys.argv[1].strip().lower(),int(sys.argv[2])
try:
    m=re.match(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?',s); h=int(m.group(1)); mi=int(m.group(2) or 0); ap=m.group(3)
    if ap=='pm' and h<12: h+=12
    if ap=='am' and h==12: h=0
    now=datetime.datetime.now(); t=now.replace(hour=h,minute=mi,second=0,microsecond=0)
    if t<=now: t+=datetime.timedelta(days=1)
    print(int((t-now).total_seconds())+120)
except Exception: print(dflt)
PY
}

# one headless session for one task; returns 0 done, 1 unclear, 2 waited (limit or network), 3 blocked
run_task(){ local plan=$1 n=$2 title=$3 pass=$4
  local prompt="You are executing Task $n (\"$title\") of the implementation plan at $plan, in this repository, on branch $BRANCH.
First read the plan's Global Constraints and File map, then Task $n in full, then read .delivery/build-needs.md and any .delivery/inbox/note-* the operator left, which may answer an earlier block. Then do the task exactly as written: steps in order; where the task has a test, write it first and run it to see it fail; implement; run the test, then \`bash plugin/tests/run.sh\`, and do not go on while anything fails. Follow superpowers:executing-plans and superpowers:test-driven-development when they are available.
When a step is done, change its \`- [ ]\` (or \`- [?]\`) to \`- [x]\` in $plan, editing only that marker. Commit with the message the task gives, on this branch, never on main, and include the plan file in that commit. Where the task names a slice, log with \`bash plugin/scripts/run-log.sh dm-builder <slice> working|built '<note>'\`.
If a step needs the operator (a secret, a permission, a device, a listening choice, a bot, a login, a decision), ask once with AskUserQuestion, one sentence saying exactly what you need and how to give it; if no answer comes, append one line to .delivery/build-needs.md (\`Task $n step k: <what is needed, how to provide it>\`), mark that step \`- [?]\`, and stop this task leaving the tree clean. If the task cannot proceed because something it depends on is still \`- [?]\`, stop and say which. Never print a secret. Never modify anything under ~/work. Never merge to main.
End your output with one line: DONE $n <what was committed> or BLOCKED $n <what is needed>."
  log "pass $pass · task $n start · $title"
  local outf=".delivery/build/$(basename "$plan" .md)-task-$n-pass-$pass.out"
  # shellcheck disable=SC2086
  "$CLAUDE" -p "$prompt" --model "$MODEL" $PERMS --output-format text > "$outf" 2>&1; local rc=$?
  if grep -qiE 'usage limit|limit reached|rate limit|resets at' "$outf"; then
    local until; until=$(grep -oiE 'reset(s)? at [0-9]{1,2}(:[0-9]{2})? ?(am|pm)?' "$outf" | head -1 | sed -E 's/.*at //')
    local secs; secs=$(wait_secs "${until:-none}"); [ -n "$secs" ] || secs=${BUILD_LIMIT_WAIT:-1200}
    log "usage limit during task $n; waiting ${secs}s"; notify "Janus build: usage limit, resuming in $((secs/60)) min"; sleep "$secs"; return 2
  fi
  if grep -qiE 'ECONNRESET|ENOTFOUND|fetch failed|network error|ETIMEDOUT' "$outf"; then log "network trouble during task $n; waiting 300s"; sleep 300; return 2; fi
  local last; last=$(grep -E '^(DONE|BLOCKED) ' "$outf" | tail -1)
  case "$last" in
    DONE*)    log "task $n done · $last"; notify "Janus build: task $n done · $title"; return 0;;
    BLOCKED*) log "task $n blocked · $last"; notify "Janus build needs you: ${last:0:160}"; return 3;;
    *)        log "task $n ended rc=$rc without a verdict; next pass retries"; return 1;;
  esac
}

pass=0
while true; do
  pass=$((pass+1)); progress=0; blocked=0
  for plan in "${PLANS[@]}"; do
    [ -f "$plan" ] || { log "no such plan: $plan"; continue; }
    before=$(count_open "$plan")
    while IFS=$'\t' read -r n title; do
      [ -n "$n" ] || continue
      run_task "$plan" "$n" "$title" "$pass"; rc=$?
      [ $rc -eq 2 ] && { run_task "$plan" "$n" "$title" "$pass"; rc=$?; }
      [ $rc -eq 3 ] && blocked=$((blocked+1))
    done < <(runnable "$plan")
    after=$(count_open "$plan"); [ "$after" -lt "$before" ] && progress=1
  done
  remaining=0; for plan in "${PLANS[@]}"; do remaining=$((remaining + $(count_open "$plan"))); done
  if [ "$remaining" -eq 0 ]; then log "every step in every plan is checked; done"; notify "Janus build: every plan complete"; exit 0; fi
  [ "$ONCE" -eq 1 ] && exit 0
  if [ "$progress" -eq 0 ]; then log "pass $pass made no progress ($remaining open, $blocked blocked); sleeping ${BUILD_SLEEP:-1800}s"; sleep "${BUILD_SLEEP:-1800}"; fi
done
