#!/usr/bin/env bash
# The desk speaker. One queue, one voice, opt-in. Files in ~/.brain/voice-queue/<ms>.txt are spoken
# oldest first, only while ~/.brain/voice.on exists and ~/.brain/dnd does not. Machines never speak;
# they queue. Two voices never overlap at the desk: while the front door's loop reports listening,
# thinking or speaking, the queue holds; a loop that is not running never blocks it.
# Usage: voice-say.sh [--once]   (runs forever otherwise, as a fleet service window)
# Env: SAY_BIN — a command called as `$SAY_BIN "<line>"` instead of Kokoro+afplay (tests);
#      VOICE_NAME / KOKORO_VOICE — the voice; VOICE_STATE_URL — the loop's state endpoint.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); TTS="$HERE/../../voice/tts.sh"
Q="$HOME/.brain/voice-queue"; mkdir -p "$Q"; VOICE=${VOICE_NAME:-${KOKORO_VOICE:-am_michael}}
STATE_URL=${VOICE_STATE_URL:-http://127.0.0.1:8790/state}
SPEAK_CMD=${SAY_BIN:-}                       # the seam: it gets the line as its last argument
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

speak(){
  [ -n "$SPEAK_CMD" ] && { "$SPEAK_CMD" "$1"; return; }
  bash "$TTS" "$1" "$W/say.wav" "$VOICE" >/dev/null && afplay "$W/say.wav"
}
ok(){ [ -e "$HOME/.brain/voice.on" ] && [ ! -e "$HOME/.brain/dnd" ]; }
yield_to_loop(){                             # never talk over the concierge; never wait forever
  local i=0 body st
  while [ "$i" -lt 60 ]; do
    body=$(curl -s --max-time 1 "$STATE_URL" 2>/dev/null) || return 0   # loop down: the desk is ours
    st=$(printf %s "$body" | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p')
    case "$st" in listening|thinking|speaking) ;; *) return 0;; esac    # thinking: a reply is imminent
    sleep 1; i=$((i+1))
  done
}
pass(){
  ok || return 0
  # voice.on older than 2 hours expires, so a forgotten switch does not talk into a meeting tomorrow
  if [ -n "$(find "$HOME/.brain/voice.on" -mmin +120 2>/dev/null)" ]; then rm -f "$HOME/.brain/voice.on"; return 0; fi
  for f in $(ls "$Q" 2>/dev/null | sort); do
    ok || return 0                           # dnd raised mid-drain silences the rest of the queue
    yield_to_loop
    line=$(head -c 400 "$Q/$f"); rm -f "$Q/$f"
    [ -n "$line" ] && speak "$line"          # sequential by construction: one utterance at a time
  done
}
if [ "${1:-}" = "--once" ]; then pass; exit 0; fi
while true; do pass; sleep 2; done
