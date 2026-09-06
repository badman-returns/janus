#!/usr/bin/env bash
# The loop hears itself: Kokoro says the name and a question through the speakers, the microphone
# hears it, the concierge answers, and the stream shows the states; a second clip interrupts the
# answer. Usage: selftest-room.sh [port]   (from the fleet machine's root). Prints the state sequence.
# Env: ROOM_REPLY_DIR — with no concierge listening, write the two answers here (the machine's
# .delivery/replies) and the whole scene runs unattended. Unset: the live concierge answers. Either
# way the scene must resume and must be exactly two turns: those are checked from the stream, not the
# inbox, so a concierge that eats its notes does not change the verdict.
# The room is the wire: the Mac's default OUTPUT must be the built-in speakers. Send it to AirPods and
# the microphone never hears the name (measured: wake 0.03 against 0.995), which reads as a dead loop —
# so the script checks the default output before it plays anything, and refuses with the fix. Set
# ROOM_ANY_OUTPUT=1 to run it anyway (a wired room, a loopback device).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PORT=${1:-8790}; T=$(mktemp -d)
trap 'kill ${CURL:-} 2>/dev/null; rm -rf "$T"' EXIT      # an early exit must not leave the stream reader behind
PHRASE=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('voice',{}).get('wake_phrase','hey jarvis'))" 2>/dev/null || echo "hey jarvis")
if ! command -v SwitchAudioSource >/dev/null 2>&1; then
  echo "room selftest: note — SwitchAudioSource is missing, so the default output is unchecked (brew install switchaudio-osx)"
else
  OUT=$(SwitchAudioSource -c -t output 2>/dev/null)
  case "$OUT" in *Speakers*) ;;
    *) if [ "${ROOM_ANY_OUTPUT:-}" = 1 ]; then echo "room selftest: note — the output is \"$OUT\", not the speakers; ROOM_ANY_OUTPUT=1, going on"
       else
         BUILTIN=$(SwitchAudioSource -a -t output 2>/dev/null | grep -i 'Speakers' | head -1)
         echo "room selftest: the default output is \"$OUT\", not the built-in speakers — the room is the wire"
         echo "  fix: SwitchAudioSource -s \"${BUILTIN:-MacBook Pro Speakers}\"   (or ROOM_ANY_OUTPUT=1 to run anyway)"
         exit 1
       fi;;
  esac
fi
ANSWERED=" "
answer() {  # answer <text>: stand in for the concierge — wait for the note we have not answered yet, reply to it
  [ -n "${ROOM_REPLY_DIR:-}" ] || return 0
  local text=$1 p stem=""
  for i in $(seq 1 60); do
    p=$(ls -t .delivery/inbox/note-*.txt 2>/dev/null | head -1)
    [ -n "$p" ] && stem=$(basename "$p" .txt) || stem=""
    case "$ANSWERED" in *" $stem "*) stem="";; esac
    [ -n "$stem" ] && break
    sleep 0.5
  done
  [ -n "$stem" ] || { echo "room selftest: no note to answer"; return 1; }
  ANSWERED="$ANSWERED$stem "
  mkdir -p "$ROOM_REPLY_DIR"; printf '%s\n' "$text" > "$ROOM_REPLY_DIR/$stem.md"
  echo "room selftest: answered $stem"
}
bash "$HERE/tts.sh" "$PHRASE." "$T/wake.wav" >/dev/null; bash "$HERE/tts.sh" "What is waiting?" "$T/q.wav" >/dev/null
bash "$HERE/tts.sh" "$PHRASE, wait, why two?" "$T/cut.wav" >/dev/null   # the name leads: it interrupts whatever the echo rule thinks
bash "$HERE/tts.sh" "No, the other one." "$T/cut2.wav" >/dev/null       # no name: only the energy rule can let this one in
curl -s --max-time 3 "http://127.0.0.1:$PORT/state" | grep -q '"state"' || { echo "room selftest: nothing answering on $PORT"; exit 1; }
curl -sN "http://127.0.0.1:$PORT/stream" > "$T/stream.txt" & CURL=$!
sleep 1; afplay "$T/wake.wav"; sleep 0.3; afplay "$T/q.wav"
answer "Two things. The video is ready. Want it?" || exit 1
# `speaking` is emitted when the sentence is queued, not when it sounds: wait for the sound itself, or the
# interruption lands on a silent room, over an uncalibrated echo, with the name masked by the first syllable.
for i in $(seq 1 90); do sed -n '/"state": "speaking"/,$p' "$T/stream.txt" | grep -qE '"v": (0\.[1-9]|1)' && break; sleep 1; done
sleep 0.7; afplay "$T/cut.wav"
answer "Because of the walk-in." || exit 1
# The resume can only come after the answering reply is spoken, and the real concierge takes 30 s to
# think and 30 s to answer: poll for it until the loop is idle again (nothing left to resume) or 180 s.
for i in $(seq 1 360); do
  grep -q 'Back to where I was' "$T/stream.txt" && break
  [ "$(grep -o '"state": "[a-z]*"' "$T/stream.txt" | tail -1)" = '"state": "idle"' ] && break
  sleep 0.5
done
cp "$T/stream.txt" "$T/scene.txt"          # the scene proper; the probe below deliberately adds a turn to the stream
# Soft probe, printed and never fatal: with the resumed reply audibly playing, does a nameless voice
# still get in on the energy rule alone? Wait for a real playback level first, or we test silence.
for i in $(seq 1 20); do sed -n '/Back to where I was/,$p' "$T/stream.txt" | grep -qE '"v": (0\.[1-9]|1)' && break; sleep 0.5; done
BEFORE=$(grep -c '"door": "wake"' "$T/stream.txt")
afplay "$T/cut2.wav"; sleep 4
if [ "$(grep -c '"door": "wake"' "$T/stream.txt")" -gt "$BEFORE" ]; then echo "room selftest: the energy rule let a nameless voice in"
else echo "room selftest: note — the nameless interrupt did not fire; the name is the reliable door"; fi
sleep 2; kill $CURL 2>/dev/null
grep -o '"state": "[a-z]*"' "$T/stream.txt" | uniq | tr '\n' ' '; echo
cp "$T/stream.txt" .delivery/voice-selftest-stream.txt
for s in listening thinking speaking; do grep -q "\"state\": \"$s\"" "$T/scene.txt" || { echo "room selftest: never saw $s"; exit 1; }; done
grep -q 'Back to where I was' "$T/scene.txt" || { echo "room selftest: never resumed after the interruption"; exit 1; }
# One turn is one note. A false alarm writes no note and emits no `thinking`, so it is already out of
# this count — that is what {"t": "false_alarm"} on the stream is: a turn that ended without becoming one.
TURNS=$(grep -o '"note": "note-[^"]*"' "$T/scene.txt" | sort -u | wc -l | tr -d ' ')
[ "$TURNS" -eq 2 ] || { echo "room selftest: $TURNS turns, expected 2 — Janus interrupted himself"; exit 1; }
echo "room selftest: ok"
