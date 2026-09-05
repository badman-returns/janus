#!/usr/bin/env bash
# Does the name hold? accept.sh <model.onnx|bundled-name> <hour.wav> <ten-triggers.wav>
# Runs openWakeWord over both recordings in 80 ms frames — the same frames the loop hears — and
# prints false triggers per hour on the first and true triggers out of ten on the second.
# Pass (exit 0): at most one false trigger per hour and at least nine of ten true triggers.
#
#   bash voice/wake/accept.sh voice/wake/hey_janus.onnx ~/.brain/wake/hour.wav ~/.brain/wake/ten.wav
#
# The hour is an hour of ordinary desk work, the operator's to record and long-lived, so through the
# machine:  dm-run.sh record "ffmpeg -f avfoundation -i ':1' -t 3600 -ac 1 -ar 16000 ~/.brain/wake/hour.wav"
# ten.wav is Kokoro's ten "hey Janus" from train.sh for the first pass; re-record it in your own
# voice at two metres for the real one.
# Env: WAKE_THRESHOLD (0.5, what loop.py uses), WAKE_COOLDOWN (1.5) seconds deaf after a hit.
set -uo pipefail
[ $# -eq 3 ] || { sed -n '2,9p' "$0"; exit 2; }
for f in "$2" "$3"; do [ -s "$f" ] || { echo "accept: no recording at $f"; exit 2; }; done
HERE="$(cd "$(dirname "$0")" && pwd)"
exec "$(dirname "$HERE")/.venv/bin/python" - "$@" <<'PY'
import os, subprocess, sys, numpy as np
from openwakeword.model import Model
SR, FRAME = 16000, 1280   # 80 ms frames: what openWakeWord wants (loop.py uses the same)
TH = float(os.environ.get("WAKE_THRESHOLD", 0.5))
DEAF = int(float(os.environ.get("WAKE_COOLDOWN", 1.5)) * SR / FRAME)
model, hour, ten = sys.argv[1:4]

def frames(path):
    """Every recording through ffmpeg, so a 44.1 kHz stereo phone memo counts the same as the mic's."""
    p = subprocess.Popen(["ffmpeg", "-loglevel", "error", "-i", path,
                          "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"], stdout=subprocess.PIPE)
    while True:
        b = p.stdout.read(FRAME * 2)
        if len(b) < FRAME * 2:
            p.stdout.close(); p.wait(); return
        yield np.frombuffer(b, dtype=np.int16)

def count(path):
    """Triggers and seconds. One utterance is one trigger: after a hit the model resets and goes
    deaf, the way loop.py resets so a single 'hey Janus' does not read as fifteen."""
    m = Model(wakeword_models=[model], inference_framework="onnx")
    n = deaf = 0; frames_seen = 0
    for f in frames(path):
        frames_seen += 1
        if deaf:
            deaf -= 1; continue
        if max(m.predict(f).values()) > TH:
            n += 1; m.reset(); deaf = DEAF
    return n, frames_seen * FRAME / SR

fp, secs = count(hour)
fp_hr = fp * 3600.0 / secs if secs else 0.0
tp, _ = count(ten)
print(f"false triggers: {fp} in {secs / 60:.1f} min → {fp_hr:.2f}/hour   {os.path.basename(hour)}")
print(f"true triggers:  {tp}/10   {os.path.basename(ten)}")
ok = fp_hr <= 1.0 and tp >= 9
print(f"accept: {'PASS' if ok else 'FAIL'}  (need ≤1 false/hour and ≥9/10 true, threshold {TH})")
sys.exit(0 if ok else 1)
PY
