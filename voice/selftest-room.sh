#!/usr/bin/env bash
# The loop hears itself: Kokoro says the name and a question through the speakers, the microphone
# hears it, the concierge answers, and the stream shows the states; a second clip interrupts the
# answer. Usage: selftest-room.sh [port]   (from the fleet machine's root). Prints the state sequence.
# Env: ROOM_REPLY_DIR — with no concierge listening, write the two answers here (the machine's
# .delivery/replies) and the whole scene runs unattended. Unset: the live concierge answers.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PORT=${1:-8790}; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PHRASE=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('voice',{}).get('wake_phrase','hey jarvis'))" 2>/dev/null || echo "hey jarvis")
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
bash "$HERE/tts.sh" "$PHRASE." "$T/wake.wav" >/dev/null; bash "$HERE/tts.sh" "What is waiting?" "$T/q.wav" >/dev/null; bash "$HERE/tts.sh" "Wait, why two?" "$T/cut.wav" >/dev/null
curl -sN "http://127.0.0.1:$PORT/stream" > "$T/stream.txt" & CURL=$!
sleep 1; afplay "$T/wake.wav"; sleep 0.3; afplay "$T/q.wav"
answer "Two things. The video is ready. Want it?"
for i in $(seq 1 90); do grep -q '"state": "speaking"' "$T/stream.txt" && break; sleep 1; done
sleep 1.5; afplay "$T/cut.wav"
answer "Because of the walk-in."
sleep 30; kill $CURL 2>/dev/null
grep -o '"state": "[a-z]*"' "$T/stream.txt" | uniq | tr '\n' ' '; echo
cp "$T/stream.txt" .delivery/voice-selftest-stream.txt
for s in listening thinking speaking; do grep -q "\"state\": \"$s\"" "$T/stream.txt" || { echo "room selftest: never saw $s"; exit 1; }; done
echo "room selftest: ok"
