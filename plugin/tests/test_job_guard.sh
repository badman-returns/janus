#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; JG="$HERE/../scripts/job-guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_job_guard: $1"; exit 1; }
mkdir -p "$T/home/.brain"
HOME="$T/home" bash -c "source '$JG'; echo ran" | grep -q ran || fail "guard blocked when not paused"
touch "$T/home/.brain/PAUSED"
OUT=$(HOME="$T/home" bash -c "source '$JG'; echo ran"); [ -z "$OUT" ] || fail "guard did not stop the job when PAUSED"

# The kill switch is only real if every scheduled job honours it: while PAUSED exists each must exit
# 0 having said and done nothing at all. `claude` is stubbed so a job that ignores the guard cannot
# spend a real headless run to fail this test.
mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\necho STUB CLAUDE RAN\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
for job in brief miner lint-job; do
  OUT=$(HOME="$T/home" PATH="$T/bin:$PATH" bash "$HERE/../scripts/$job.sh" 2>&1) \
    || fail "$job.sh exited $? while PAUSED, expected 0"
  [ -z "$OUT" ] || fail "$job.sh did not stop at the guard while PAUSED, it said: $OUT"
done
echo "PASS test_job_guard"
