#!/usr/bin/env bash
# tts.sh renders with Kokoro when voice/.venv and the model exist and falls back to `say` otherwise,
# so proof narration and voice messages never break on a machine without the model.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; TTS="$HERE/../../voice/tts.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_tts_fallback: $1"; exit 1; }
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nout=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done; ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=440:duration=0.3" "$out"\n' > "$T/bin/say"; chmod +x "$T/bin/say"
res=$(PATH="$T/bin:$PATH" TTS_FORCE_SAY=1 bash "$TTS" "one two three" "$T/o.wav") || fail "exited $?"
[ "$res" = fallback ] || fail "expected the word fallback, got: $res"
[ -s "$T/o.wav" ] || fail "no wav written"
ffprobe -v error -show_entries stream=sample_rate -of csv=p=0 "$T/o.wav" | grep -q '^24000$' || fail "wav is not 24 kHz"
echo "PASS test_tts_fallback"
