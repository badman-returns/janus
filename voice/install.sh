#!/usr/bin/env bash
# Create voice/.venv, install the pinned packages, put the Kokoro and wake-word models under
# ~/.brain/models, render the three sample voices, and prove Kokoro with one spoken line.
# Re-runnable. Usage: bash voice/install.sh   Env: KOKORO_FILES_DIR — a folder that already holds
# kokoro-v1.0.onnx and voices-v1.0.bin (copied instead of downloaded).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; M="$HOME/.brain/models"; mkdir -p "$M/samples"
command -v espeak-ng >/dev/null || brew install espeak-ng
[ -x "$HERE/.venv/bin/python" ] || python3 -m venv "$HERE/.venv"
"$HERE/.venv/bin/pip" install -q --upgrade pip
"$HERE/.venv/bin/pip" install -q -r "$HERE/requirements.txt"
K=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
for f in kokoro-v1.0.onnx voices-v1.0.bin; do
  [ -s "$M/$f" ] && continue
  if [ -n "${KOKORO_FILES_DIR:-}" ] && [ -s "$KOKORO_FILES_DIR/$f" ]; then cp "$KOKORO_FILES_DIR/$f" "$M/$f"; else curl -L --progress-bar -o "$M/$f" "$K/$f"; fi
done
"$HERE/.venv/bin/python" -c "from openwakeword import utils; utils.download_models(['hey_jarvis'])"
for v in af_heart am_michael bm_george; do
  bash "$HERE/tts.sh" "You asked whether the badge should read Recorded late. I checked the desk scheduling slice; two files changed and the tests pass. I recommend approving it." "$M/samples/kokoro-$v.wav" "$v" >/dev/null
done
rm -f /tmp/janus-ready.wav
rc=0; out=$(bash "$HERE/tts.sh" "Janus is ready." /tmp/janus-ready.wav "${KOKORO_VOICE:-am_michael}") || rc=$?
[ "$rc" = 0 ] && [ -s /tmp/janus-ready.wav ] && [ "$out" != fallback ] || { echo "install: Kokoro did not render (rc=$rc out=${out:-none}); check espeak-ng and the model files" >&2; exit 1; }
afplay /tmp/janus-ready.wav
echo "voice: installed. models in $M; samples in $M/samples"
