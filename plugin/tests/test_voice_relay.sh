#!/usr/bin/env bash
# loop.py's reply watcher carries another machine's answer to the desk. The concierge routes an
# office question with fleet-route.sh; that machine answers into its own .delivery/replies, and the
# watcher shows it with `via: <machine>` and files a relay note in the fleet inbox so the concierge
# has the answer in context. The fleet's own replies are untouched by any of it.
# numpy is stubbed (the watcher needs no audio) so this runs without voice/.venv; tmux is stubbed so
# the nudge can never reach the real fleet session.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; VOICE="$HERE/../../voice"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_voice_relay: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/bin" "$T/fleet/.delivery/replies" "$T/mach-b/.delivery/replies"
cat > "$T/home/.delivery-machine/registry.json" <<JSON
{"relayfleet": {"dir": "$T/fleet", "session": "dm-relayfleet"},
 "relayb":     {"dir": "$T/mach-b", "session": "dm-relayb"}}
JSON
echo '{"project": "relayfleet"}' > "$T/fleet/.delivery/config.json"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/tmux.log"\ncase "$1" in list-windows) echo "@1 claude";; capture-pane) printf "❯ \\n";; esac\nexit 0\n' "$T" > "$T/bin/tmux"
chmod +x "$T/bin/tmux"
echo 'Answered long ago.' > "$T/mach-b/.delivery/replies/note-1-tg-old.md"   # already there: skipped at startup

cd "$T/fleet" || fail "no fleet dir"
HOME="$T/home" PATH="$T/bin:$PATH" T="$T" VOICE="$VOICE" python3 - <<'PY' || fail "watcher assertions failed (above)"
import os, sys, threading, time, types
sys.modules.setdefault('numpy', types.ModuleType('numpy'))       # the watcher touches no audio
sys.path.insert(0, os.environ['VOICE'])
import loop
T = os.environ['T']; got = []
threading.Thread(target=loop.watch_replies, args=(lambda stem, s, h: got.append((stem, s, h)),), daemon=True).start()
time.sleep(0.6)                                                  # let it seed `seen` with what is already there
open(f'{T}/mach-b/.delivery/replies/note-9-tg-office.md', 'w').write('via: wrong\nspeak: no\n\nThe office seat says yes. Ship it.\n')
open(f'{T}/fleet/.delivery/replies/note-8-voice-mine.md', 'w').write('via: keepme\n\nMine.\n')
end = time.time() + 15
while time.time() < end and not (len(got) == 2 and os.path.exists(f'{T}/fleet/.delivery/.nudge')): time.sleep(0.1)
by = {g[0]: g for g in got}
assert len(got) == 2, 'expected 2 callbacks, got %r' % (got,)     # the pre-existing reply is not one of them
stem, sents, h = by['note-9-tg-office']
assert h['via'] == 'relayb', 'via not overridden with the machine name: %r' % (h,)
assert h['speak'] == 'no', 'other headers dropped: %r' % (h,)     # only via is ours
assert sents == ['The office seat says yes.', 'Ship it.'], sents
assert by['note-8-voice-mine'][2]['via'] == 'keepme', 'our own reply had its via rewritten'
print('ok: 2 callbacks, via=relayb, our own reply untouched')
PY

notes=("$T"/fleet/.delivery/inbox/note-*-relay-*.txt)
[ -e "${notes[0]}" ] || fail "no relay note in the fleet inbox"
[ "${#notes[@]}" = 1 ] || fail "expected one relay note, got ${#notes[@]}: ${notes[*]}"   # never for our own reply
case "$(basename "${notes[0]}")" in note-*-relay-relayb-the-office-seat-says-yes-ship-it.txt) ;;
  *) fail "relay note misnamed: $(basename "${notes[0]}")" ;; esac
head -1 "${notes[0]}" | grep -qE '^from: relay relayb [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}$' || fail "bad header: $(head -1 "${notes[0]}")"
grep -q '^The office seat says yes. Ship it.$' "${notes[0]}" || fail "body missing: $(cat "${notes[0]}")"
[ -s "$T/fleet/.delivery/.nudge" ] || fail "the concierge was not nudged"
grep -q 'send-keys .* /dm process the pending items' "$T/tmux.log" || fail "nudge line wrong: $(cat "$T/tmux.log")"
echo "PASS test_voice_relay"
