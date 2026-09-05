#!/usr/bin/env bash
# Text -> Opus voice file for a Telegram voice message (sendVoice takes .ogg/opus); the concierge
# writes it into an outbox. One voice everywhere: the render goes through voice/tts.sh (Kokoro, with
# its own `say` fallback), then ffmpeg encodes the wav to opus 32k mono 48 kHz.
# Usage: tts-ogg.sh "<text>" <out.ogg> [voice]   Env: KOKORO_VOICE — default voice.
set -euo pipefail
TEXT=${1:?text}; OUT=${2:?out.ogg}; VOICE=${3:-${KOKORO_VOICE:-am_michael}}
HERE=$(cd "$(dirname "$0")" && pwd); W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
bash "$HERE/../../voice/tts.sh" "$TEXT" "$W/t.wav" "$VOICE" >/dev/null
ffmpeg -loglevel error -y -i "$W/t.wav" -c:a libopus -b:a 32k -ac 1 -ar 48000 "$OUT"
echo "$OUT"
