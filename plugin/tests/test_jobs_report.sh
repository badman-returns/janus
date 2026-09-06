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
HOME="$H" DM_CLAUDE_BIN="$H/bin/claude" PATH="$H/bin:$PATH" bash "$S/miner.sh" >/dev/null 2>&1
rc=$?; [ $rc -eq 0 ] || fail "miner exited $rc with no Cognee, expected 0"
grep -q "cognee-memory plugin not installed" "$H/.brain/jobs.log" \
  || fail "the miner skipped Cognee without saying so: $(cat "$H/.brain/jobs.log" 2>/dev/null)"
[ -z "$(ls "$B/.delivery/outbox")" ] || fail "the miner wrote to the outbox with no Cognee"

# With the plugin in place it runs — and a failing claude reaches both the log and the phone.
mkdir -p "$H/.claude-tsg/plugins/cache/cognee/cognee-memory/1.0.0"
for job in brief miner; do
  : > "$H/.brain/jobs.log"; rm -f "$B"/.delivery/outbox/*
  HOME="$H" DM_CLAUDE_BIN="$H/bin/claude" PATH="$H/bin:$PATH" bash "$S/$job.sh" >/dev/null 2>&1
  rc=$?; [ $rc -ne 0 ] || fail "$job.sh exited 0 after claude failed"
  grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8} $job: claude failed rc=1 \(see \.delivery/pickup\.log\)$" \
    "$H/.brain/jobs.log" || fail "$job.sh left no failure line in jobs.log: $(cat "$H/.brain/jobs.log")"
  ls "$B"/.delivery/outbox/*-"$job"-failed.txt >/dev/null 2>&1 \
    || fail "$job.sh told the log but not the phone"
done

# The likelier failure: claude exits 0 having written nothing — a refused tool call, a truncated
# answer. The exit code says the job ran; only the artefact says it worked.
printf '#!/usr/bin/env bash\nexit 0\n' > "$H/bin/claude-quiet"; chmod +x "$H/bin/claude-quiet"
for job in brief miner; do
  : > "$H/.brain/jobs.log"; rm -f "$B"/.delivery/outbox/*
  HOME="$H" DM_CLAUDE_BIN="$H/bin/claude-quiet" PATH="$H/bin:$PATH" bash "$S/$job.sh" >/dev/null 2>&1
  rc=$?; [ $rc -eq 1 ] || fail "$job.sh exited $rc after claude wrote nothing, expected 1"
  grep -q "$job: claude .*nothing" "$H/.brain/jobs.log" \
    || fail "$job.sh left no silent-failure line in jobs.log: $(cat "$H/.brain/jobs.log")"
  ls "$B"/.delivery/outbox/*-"$job"-failed.txt >/dev/null 2>&1 \
    || fail "$job.sh produced nothing and told nobody"
done

# an empty brain pointer used to make `cd ""` a no-op and run the job in launchd's cwd
: > "$H/.brain/jobs.log"; : > "$H/.delivery-machine/brain"
HOME="$H" DM_CLAUDE_BIN="$H/bin/claude-quiet" PATH="$H/bin:$PATH" bash "$S/brief.sh" >/dev/null 2>&1
rc=$?; [ $rc -eq 1 ] || fail "brief.sh with an empty brain pointer exited $rc, expected 1"
grep -q "no brain pointer" "$H/.brain/jobs.log" || fail "empty brain pointer not logged"
echo "$B" > "$H/.delivery-machine/brain"

# launchd is handed nothing unasked but the brief and the lint: the miner waits on Cognee and the
# foundry builds unattended, so each has to be named.
cat > "$H/bin/launchctl" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$T/launchctl.log"
[ "\$1" = print ] && echo "	last exit code = 0"
exit 0
EOF
chmod +x "$H/bin/launchctl"; : > "$T/launchctl.log"
OUT=$(HOME="$H" DM_CLAUDE_BIN="$H/bin/claude" PATH="$H/bin:$PATH" bash "$S/install-jobs.sh" 2>&1) || fail "install-jobs exited $?"
# a job launchd refuses to execute (exit 126, Full Disk Access) must be visible at install time
[ "$(echo "$OUT" | grep -c 'last exit code = 0')" = 2 ] || fail "install did not report each job's last exit code: $OUT"
echo "$OUT" | grep -q 'Full Disk Access >' && fail "a clean exit code printed the Full Disk Access advice"
grep -q kickstart "$T/launchctl.log" && fail "install kickstarted a job with INSTALL_JOBS_KICK unset"
for j in brief lint; do
  [ -f "$H/Library/LaunchAgents/com.brain.$j.plist" ] || fail "$j was not installed by default"
done
for j in miner foundry; do
  [ -f "$H/Library/LaunchAgents/com.brain.$j.plist" ] && fail "$j was installed with nothing asking for it"
  grep -q "com.brain.$j" "$T/launchctl.log" && fail "launchctl was told to load $j with nothing asking for it"
done
echo "PASS test_jobs_report"
