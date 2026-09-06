#!/usr/bin/env bash
# What the scheduled jobs say when they do NOT run, and which of them launchd may load unasked.
# The silent failure is the dangerous one: a missing or rate-limited `claude` used to leave no trace
# in the log and nothing on the phone, so a brief could stop arriving for a week unnoticed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_jobs_report: $1"; exit 1; }
H="$T/home"; B="$T/brain"
mkdir -p "$H/.brain" "$H/.delivery-machine" "$H/bin" "$B/.delivery/outbox"
echo "$B" > "$H/.delivery-machine/brain"
printf '#!/usr/bin/env bash\nexit 1\n' > "$H/bin/claude"; chmod +x "$H/bin/claude"   # a rate-limited seat

# The miner stops on its own until Cognee is installed — there are no captured sessions to mine.
HOME="$H" PATH="$H/bin:$PATH" bash "$S/miner.sh" >/dev/null 2>&1
rc=$?; [ $rc -eq 0 ] || fail "miner exited $rc with no Cognee, expected 0"
grep -q "cognee-memory plugin not installed" "$H/.brain/jobs.log" \
  || fail "the miner skipped Cognee without saying so: $(cat "$H/.brain/jobs.log" 2>/dev/null)"
[ -z "$(ls "$B/.delivery/outbox")" ] || fail "the miner wrote to the outbox with no Cognee"

# With the plugin in place it runs — and a failing claude reaches both the log and the phone.
mkdir -p "$H/.claude-tsg/plugins/cache/cognee/cognee-memory/1.0.0"
for job in brief miner; do
  : > "$H/.brain/jobs.log"; rm -f "$B"/.delivery/outbox/*
  HOME="$H" PATH="$H/bin:$PATH" bash "$S/$job.sh" >/dev/null 2>&1
  rc=$?; [ $rc -ne 0 ] || fail "$job.sh exited 0 after claude failed"
  grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8} $job: claude failed rc=1 \(see \.delivery/pickup\.log\)$" \
    "$H/.brain/jobs.log" || fail "$job.sh left no failure line in jobs.log: $(cat "$H/.brain/jobs.log")"
  ls "$B"/.delivery/outbox/*-"$job"-failed.txt >/dev/null 2>&1 \
    || fail "$job.sh told the log but not the phone"
done

# launchd is handed nothing unasked but the brief and the lint: the miner waits on Cognee and the
# foundry builds unattended, so each has to be named.
printf '#!/usr/bin/env bash\necho "$@" >> "%s/launchctl.log"\n' "$T" > "$H/bin/launchctl"
chmod +x "$H/bin/launchctl"; : > "$T/launchctl.log"
HOME="$H" PATH="$H/bin:$PATH" bash "$S/install-jobs.sh" >/dev/null 2>&1 || fail "install-jobs exited $?"
for j in brief lint; do
  [ -f "$H/Library/LaunchAgents/com.brain.$j.plist" ] || fail "$j was not installed by default"
done
for j in miner foundry; do
  [ -f "$H/Library/LaunchAgents/com.brain.$j.plist" ] && fail "$j was installed with nothing asking for it"
  grep -q "com.brain.$j" "$T/launchctl.log" && fail "launchctl was told to load $j with nothing asking for it"
done
echo "PASS test_jobs_report"
