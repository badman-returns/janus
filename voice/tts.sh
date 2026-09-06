#!/usr/bin/env bash
# One voice everywhere. tts.sh "<text>" <out.wav> [voice] renders with Kokoro from voice/.venv and
# falls back to macOS `say` when the venv or the model is missing, so nothing that speaks breaks.
# Env: TTS_FORCE_SAY=1 forces the fallback (tests); KOKORO_VOICE default voice; SAY_VOICE (default Aman);
#      TTS_DEBUG=1 prints the resolved voice on stderr.
set -uo pipefail
TEXT=${1:?text}; OUT=${2:?out.wav}
HERE="$(cd "$(dirname "$0")" && pwd)"; PY="$HERE/.venv/bin/python"
# One voice everywhere, decided in one place: the argument, the environment, the fleet machine's
# `voice.kokoro_voice`, then the built-in. Every speech path but the loop comes through here.
fleet_voice(){
  local d; d=$(bash "$HERE/../plugin/scripts/machine-dir.sh" fleet tts 2>/dev/null) && [ -n "$d" ] || return 0
  python3 -c "import json,sys;print((json.load(open(sys.argv[1]+'/.delivery/config.json')).get('voice') or {}).get('kokoro_voice') or '')" "$d" 2>/dev/null
}
VOICE=${3:-${KOKORO_VOICE:-$(fleet_voice)}}
[ -n "$VOICE" ] || VOICE=am_michael
[ -n "${TTS_DEBUG:-}" ] && echo "tts: voice=$VOICE" >&2
if [ -z "${TTS_FORCE_SAY:-}" ] && [ -x "$PY" ] && [ -s "$HOME/.brain/models/kokoro-v1.0.onnx" ]; then
  P=$(brew --prefix 2>/dev/null || echo /opt/homebrew)
  export ESPEAK_DATA_PATH="${ESPEAK_DATA_PATH:-$P/share/espeak-ng-data}" PHONEMIZER_ESPEAK_LIBRARY="${PHONEMIZER_ESPEAK_LIBRARY:-$P/lib/libespeak-ng.dylib}"
  "$PY" "$HERE/tts.py" --out "$OUT" --voice "$VOICE" "$TEXT" >/dev/null 2>&1 && exit 0
  echo "tts: kokoro failed, falling back to say" >&2
fi
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
say -v "${SAY_VOICE:-Aman}" -o "$W/t.aiff" "$TEXT" && ffmpeg -loglevel error -y -i "$W/t.aiff" -ar 24000 -ac 1 "$OUT" && echo fallback
