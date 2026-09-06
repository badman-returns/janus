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

# One voice everywhere: with nothing named, tts.sh resolves the fleet machine's voice.kokoro_voice.
# The render is forced down the `say` path, so the resolved name is read off TTS_DEBUG's stderr line.
mkdir -p "$T/home/.delivery-machine" "$T/fleet/.delivery"
echo "{\"fleet\":{\"dir\":\"$T/fleet\"}}" > "$T/home/.delivery-machine/registry.json"
echo '{"project":"fleet","voice":{"kokoro_voice":"af_sarah"}}' > "$T/fleet/.delivery/config.json"
v(){ HOME="$1" PATH="$T/bin:$PATH" KOKORO_VOICE= TTS_FORCE_SAY=1 TTS_DEBUG=1 bash "$TTS" one "$T/v.wav" ${2:+"$2"} 2>&1 >/dev/null; }
v "$T/home"     | grep -q '^tts: voice=af_sarah$'  || fail "the fleet's voice was not resolved: $(v "$T/home")"
v "$T/home" bm_george | grep -q '^tts: voice=bm_george$' || fail "an explicit voice lost to the fleet's"
v "$T/nohome"   | grep -q '^tts: voice=am_michael$' || fail "no registry did not fall back to the built-in"
echo "PASS test_tts_fallback"
