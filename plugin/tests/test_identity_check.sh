#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; IC="$HERE/../scripts/identity-check.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_identity_check: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/work/repo"
echo "{\"$T/work\":{\"name\":\"work-user\",\"email\":\"t@work\",\"config_dir\":\"$T/home/.claude-alt\"}}" > "$T/home/.delivery-machine/identities.json"
cd "$T/work/repo"; git init -q; git config user.name badman-returns; git config user.email x@y
OUT=$(HOME="$T/home" CLAUDE_CONFIG_DIR="$T/home/.claude-alt" bash "$IC"); RC=$?
[ $RC = 1 ] || fail "mismatch not detected (rc $RC)"
echo "$OUT" | grep -q 'IDENTITY MISMATCH' || fail "no headline"
echo "$OUT" | grep -q 'git config --local user.name "work-user"' || fail "fix command missing: $OUT"
git config user.name work-user; git config user.email t@work
OUT=$(HOME="$T/home" CLAUDE_CONFIG_DIR="$T/home/.claude-alt" bash "$IC"); [ $? = 0 ] && [ -z "$OUT" ] || fail "clean repo flagged: $OUT"
OUT=$(HOME="$T/home" CLAUDE_CONFIG_DIR="$T/home/.claude-tsg" bash "$IC"); [ $? = 1 ] || fail "wrong account not detected"
echo "$OUT" | grep -q 'account' || fail "account mismatch not named"
cd "$T"; OUT=$(HOME="$T/home" bash "$IC"); [ $? = 0 ] || fail "unmapped path should pass"
# It refuses only when it is sure. A map it cannot read, or an entry that never says what it wants,
# is not knowledge — it must stay silent rather than accuse on every session start.
cd "$T/work/repo"; echo '{bad json' > "$T/home/.delivery-machine/identities.json"
OUT=$(HOME="$T/home" CLAUDE_CONFIG_DIR="$T/home/.claude-tsg" bash "$IC" 2>&1); [ $? = 0 ] && [ -z "$OUT" ] || fail "corrupt map should pass silently: $OUT"
echo "{\"$T/work\":{\"name\":\"work-user\"}}" > "$T/home/.delivery-machine/identities.json"
OUT=$(HOME="$T/home" CLAUDE_CONFIG_DIR="$T/home/.claude-tsg" bash "$IC" 2>&1); [ $? = 0 ] && [ -z "$OUT" ] || fail "incomplete entry should pass silently: $OUT"
# The hook runs the check BEFORE its own `[ -d .delivery ]` exit: a mapped repo that is not a Janus
# project still gets checked. And it stays fail-open — loud in the transcript, exit 0 regardless.
echo "{\"$T/work\":{\"name\":\"work-user\",\"email\":\"t@work\",\"config_dir\":\"$T/home/.claude-alt\"}}" > "$T/home/.delivery-machine/identities.json"
cd "$T/work/repo"; [ -d .delivery ] && fail "fixture must have no .delivery"
OUT=$(HOME="$T/home" CLAUDE_CONFIG_DIR="$T/home/.claude-tsg" bash "$HERE/../scripts/session-start.sh" 2>&1); RC=$?
[ $RC = 0 ] || fail "hook must stay fail-open (rc $RC): $OUT"
echo "$OUT" | grep -q 'IDENTITY MISMATCH' || fail "hook skipped the check outside a Janus project: $OUT"
echo "$OUT" | grep -q 'restart this session with CLAUDE_CONFIG_DIR=' || fail "remediation not restart-worded: $OUT"
echo "PASS test_identity_check"
