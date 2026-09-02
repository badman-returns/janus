#!/usr/bin/env bash
# janus.sh --list on a synthetic fleet: waiting counts exclude operator-written files,
# the recap comes from the last ledger line, a machine whose directory is gone says so,
# and an empty/absent registry is not an error. The picker's key handling is a TTY thing
# and undrivable from here; this covers everything it renders from.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/janus.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL test_janus: $1"; exit 1; }

mk(){ mkdir -p "$T/$1/.delivery/inbox"; }
mk alpha; mk beta

# alpha — two things waiting, plus operator-written files that must NOT count
: > "$T/alpha/.delivery/inbox/gate-login.txt"
: > "$T/alpha/.delivery/inbox/ask-1234-pdf-library.txt"
: > "$T/alpha/.delivery/inbox/reply-1234-pdf-library.txt"
: > "$T/alpha/.delivery/inbox/note-9-thought.txt"
: > "$T/alpha/.delivery/inbox/.gitkeep"
cat > "$T/alpha/.delivery/runs.jsonl" <<'JSONL'
{"ts":"2026-09-02T10:00:00Z","agent":"dm-builder","slice":"login","status":"built","note":"first"}
{"ts":"2026-09-02T11:00:00Z","agent":"dm-verifier","slice":"login","status":"done","note":"proof written"}
JSONL

# beta — nothing waiting, no ledger at all
cat > "$T/reg.json" <<JSON
{ "alpha": { "dir": "$T/alpha", "session": "dm-alpha-nope", "port": 5501, "ttyd_port": 5601 },
  "beta":  { "dir": "$T/beta",  "session": "dm-beta-nope",  "port": 5502, "ttyd_port": 5602 },
  "ghost": { "dir": "$T/was-deleted", "session": "dm-ghost", "port": 5503, "ttyd_port": null } }
JSON

out=$(DM_REGISTRY="$T/reg.json" bash "$S" --list) || fail "--list exited $?"
get(){ printf '%s\n' "$out" | awk -F'\t' -v n="$1" '$1==n {print $'"$2"'}'; }

[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 3 ] || fail "expected 3 rows, got: $out"

# waiting: gate + ask count; reply-, note- and dotfiles do not
[ "$(get alpha 4)" = 2 ] || fail "alpha waiting should be 2, got '$(get alpha 4)'"
[ "$(get beta 4)"  = 0 ] || fail "beta waiting should be 0, got '$(get beta 4)'"

# these sessions do not exist, so nothing is alive
[ "$(get alpha 3)" = 0 ] || fail "alpha should not be alive"

# recap is the LAST ledger line, agent prefix stripped, note appended
case "$(get alpha 7)" in
  "verifier · login · done — proof written") : ;;
  *) fail "alpha recap wrong: '$(get alpha 7)'" ;;
esac
# no ledger -> falls back, must still say something and never be empty
[ -n "$(get beta 7)" ] || fail "beta recap empty"
case "$(get beta 7)" in *"no runs yet"*) : ;; *) fail "beta recap should say no runs yet: '$(get beta 7)'";; esac

# a registered directory that no longer exists is reported, not a crash
case "$(get ghost 7)" in *"gone"*) : ;; *) fail "ghost should report a missing directory: '$(get ghost 7)'";; esac

# ports survive to the renderer, which uses them for the dashboard key
[ "$(get alpha 5)" = 5501 ] || fail "alpha port wrong: '$(get alpha 5)'"

# the rendered picker (no TTY) names every machine and does not hang
render=$(DM_REGISTRY="$T/reg.json" bash "$S" < /dev/null) || fail "render exited $?"
for n in alpha beta ghost; do
  printf '%s' "$render" | grep -q "$n" || fail "render missing $n"
done
# the header counts MACHINES that want attention, not items — you act on a machine
printf '%s' "$render" | grep -q "1 needs you" || fail "render should say 1 machine needs you"
printf '%s' "$render" | grep -q "2 waiting"   || fail "alpha's row should show its 2 items"

# macOS ships bash 3.2, which rejects a fractional read timeout ("read: 0.4: invalid timeout
# specification") and returns nothing — the arrow keys then arrive as separate keystrokes and
# navigation silently stops working. Keep every -t whole.
grep -nE 'read[^|;]*-t +[0-9]+\.[0-9]' "$HERE/../scripts/janus.sh" \
  && fail "fractional read -t timeout: bash 3.2 rejects it and the arrow keys break"

# a lone ESC must not be bound to anything: an early timeout would otherwise quit the
# launcher out from under the operator mid-keystroke
grep -qE "^\s+q\)" "$HERE/../scripts/janus.sh" || fail "q should be the quit key"
grep -E "\\e'\)" "$HERE/../scripts/janus.sh" | grep -q "exit" \
  && fail "bare ESC is bound to exit"

# an absent registry is an empty fleet, not a failure
DM_REGISTRY="$T/nope.json" bash "$S" --list >/dev/null 2>&1 || fail "missing registry should exit 0"

echo "PASS test_janus"
