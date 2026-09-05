#!/usr/bin/env bash
# "hey Janus": render the training audio with Kokoro, then hand it to openWakeWord's own trainer.
# Five phases, each resumable — rerunning skips whatever is already on disk:
#   render → download gate → train venv → training data → openwakeword.train → voice/wake/hey_janus.onnx
#
#   bash voice/wake/train.sh                 render the audio, then stop at the gate with the sizes
#   WAKE_MAX_GB=30 bash voice/wake/train.sh  let it download (~25 GB) and train (1-2 h of CPU)
#
# Env: WAKE_MAX_GB (6) download ceiling; WAKE_SKIP_RENDER=1 the audio is already rendered;
#      WAKE_STEPS (50000) training steps; WAKE_BACKGROUND_DIR a directory of your own noise
#      audio instead of the 7.7 GB Free Music Archive download.
# Nothing here belongs in git: every clip and every byte of data lives under ~/.brain/wake.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PY="$(dirname "$HERE")/.venv/bin/python"
export W="$HOME/.brain/wake" PHRASE="hey Janus"
DATA="$W/data"; OUT="$W/out"; TVENV="$W/venv-train"; MODEL=hey_janus
MAX_GB=${WAKE_MAX_GB:-6}
mkdir -p "$W" "$DATA" "$OUT"

# ── 1. the voices say the name ──────────────────────────────────────────────────
# 600 positives and 200 near-misses across every English Kokoro voice at speeds 0.85-1.2, plus
# ten.wav: ten "hey Janus" with 3 s gaps, the first-pass true-trigger file for accept.sh.
# One process, one model load — shelling out per clip would spend an hour loading Kokoro 811 times.
if [ -z "${WAKE_SKIP_RENDER:-}" ]; then
  echo "### render: 600 positives + 200 near-misses + ten.wav → $W"
  "$PY" - <<'PY' || exit 1
import os, random, subprocess, numpy as np, soundfile as sf
from kokoro_onnx import Kokoro
W, PHRASE = os.environ["W"], os.environ["PHRASE"]
m = os.path.expanduser("~/.brain/models")
k = Kokoro(os.path.join(m, "kokoro-v1.0.onnx"), os.path.join(m, "voices-v1.0.bin"))
VOICES = sorted(v for v in k.get_voices() if v[:3] in ("af_", "am_", "bf_", "bm_"))  # the English ones
NEAR = ["hey James", "hey Janice", "hey Janus is", "Janus"]
random.seed(11)   # the same 800 clips every run, so a rerun resumes instead of drifting

def render(text, voice, speed, out):
    audio, sr = k.create(text, voice=voice, speed=speed, lang="en-us")
    tmp = out + ".24k.wav"; sf.write(tmp, audio, sr)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp,
                    "-ar", "16000", "-ac", "1", out], check=True)
    os.remove(tmp)

def batch(texts, n, d):
    os.makedirs(d, exist_ok=True)
    for i in range(n):
        voice = VOICES[i % len(VOICES)]                      # round-robin the voices
        text = texts[(i // len(VOICES)) % len(texts)]        # each voice says every near-miss
        speed = round(random.uniform(0.85, 1.2), 3)
        out = os.path.join(d, f"{i:04d}_{voice}_{speed}.wav")
        if not os.path.exists(out):
            render(text, voice, speed, out)
        if i % 100 == 99: print(f"  {os.path.basename(d)}: {i+1}/{n}", flush=True)

batch([PHRASE], 600, f"{W}/positives")
batch(NEAR, 200, f"{W}/adversarial")
render(PHRASE, os.environ.get("KOKORO_VOICE", "am_michael"), 1.0, f"{W}/one.wav")
clip, sr = sf.read(f"{W}/one.wav")
gap = np.zeros(3 * sr, dtype=clip.dtype)                     # 3 s of room between triggers
sf.write(f"{W}/ten.wav", np.concatenate([gap] + [np.concatenate([clip, gap])] * 10), sr)
print(f"  ten.wav: {(len(clip) + len(gap)) * 10 / sr + 3:.0f}s, ten triggers", flush=True)
PY
  echo "### render: $(ls "$W/positives" | wc -l | tr -d ' ') positives, $(ls "$W/adversarial" | wc -l | tr -d ' ') near-misses"
fi

# ── 2. the download gate ────────────────────────────────────────────────────────
# openWakeWord trains against its own pre-computed negatives, its impulse responses and hours of
# background music. Measure all of it before a byte lands, and refuse over the ceiling.
echo "### gate: sizing openWakeWord's training data (ceiling ${MAX_GB} GB)"
GB=$("$PY" - <<'PY'
import json, os, sys, urllib.request
def hf(repo, keep=lambda n: True):
    u = f"https://huggingface.co/api/datasets/{repo}?blobs=true"
    d = json.load(urllib.request.urlopen(u, timeout=90))
    return sum(s.get("size") or 0 for s in d["siblings"] if keep(s["rfilename"]))
def head(url):
    r = urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=90)
    return int(r.headers["content-length"])
rows = [("openwakeword negative features (ACAV100M, 2000 h)", hf("davidscripka/openwakeword_features", lambda n: "ACAV100M" in n)),
        ("openwakeword false-positive validation set", hf("davidscripka/openwakeword_features", lambda n: "validation" in n)),
        ("MIT environmental impulse responses", hf("davidscripka/MIT_environmental_impulse_responses"))]
if not os.environ.get("WAKE_BACKGROUND_DIR"):
    rows.append(("Free Music Archive small (background noise)", head("https://os.unil.cloud.switch.ch/fma/fma_small.zip")))
for name, n in rows:
    print(f"  {n/1e9:8.2f} GB  {name}", file=sys.stderr)
total = sum(n for _, n in rows)
print(f"  {total/1e9:8.2f} GB  TOTAL", file=sys.stderr)
print(f"{total/1e9:.2f}")
PY
) || { echo "gate: could not size the data (no network?)"; exit 1; }
[ -n "$GB" ] && awk -v g="$GB" 'BEGIN{exit !(g > 0)}' || { echo "gate: no size measured — not downloading blind"; exit 1; }
# Fails closed: only a measured total at or under the ceiling opens the gate.
if ! awk -v g="$GB" -v m="$MAX_GB" 'BEGIN{exit !(g <= m)}'; then
  cat <<EOF
### BLOCKED: openWakeWord's training data is ${GB} GB, over the ${MAX_GB} GB ceiling.
Nothing was downloaded. The rendered audio above is kept and the hey_jarvis stand-in keeps working.
To go ahead: WAKE_MAX_GB=30 bash voice/wake/train.sh   (or point WAKE_BACKGROUND_DIR at your own noise)
EOF
  exit 3
fi

# ── 3. a venv of its own ────────────────────────────────────────────────────────
# The live loop runs out of voice/.venv; torch does not go in there. Not openwakeword[full] —
# that extra pins tensorflow-cpu 2.8.1 and onnx-tf, which exist for neither this Python nor this Mac
# and are only needed for the tflite export we do not want.
if [ ! -x "$TVENV/bin/python" ]; then
  echo "### deps: building $TVENV"
  "$PY" -m venv "$TVENV" || exit 1
  "$TVENV/bin/pip" install -q --upgrade pip
  "$TVENV/bin/pip" install "openwakeword==0.6.0" torch torchaudio torchinfo torchmetrics \
    speechbrain audiomentations torch-audiomentations acoustics pronouncing pyyaml \
    mutagen datasets soundfile || exit 1
fi
TPY="$TVENV/bin/python"

# ── 4. the data ─────────────────────────────────────────────────────────────────
echo "### data: → $DATA"
"$TPY" - <<'PY' || exit 1
import os, subprocess
from huggingface_hub import snapshot_download
D = os.path.join(os.environ["W"], "data")

def fetch(url, p):
    """curl, not urlretrieve: 17 GB over a home connection needs resume (-C -), and a download that
    dies must not leave a truncated file at the final name — a rerun would take it for complete and
    feed a corrupt .npy to the trainer. Downloads to .part, renames only on success."""
    if os.path.exists(p):
        return
    print(f"  {os.path.basename(p)} …", flush=True)
    subprocess.run(["curl", "-fL", "--retry", "5", "--retry-delay", "5", "-C", "-",
                    "-o", p + ".part", url], check=True)
    os.replace(p + ".part", p)

for f in ("openwakeword_features_ACAV100M_2000_hrs_16bit.npy", "validation_set_features.npy"):
    fetch(f"https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main/{f}",
          os.path.join(D, f))
if not os.path.isdir(os.path.join(D, "mit_rirs", "16khz")):
    # openWakeWord scandirs rir_paths and hands every entry to a wav reader, so the config points at
    # the repo's 16khz/ subdirectory — the root also holds README.md and snapshot_download's .cache/.
    snapshot_download("davidscripka/MIT_environmental_impulse_responses",
                      repo_type="dataset", local_dir=os.path.join(D, "mit_rirs"))
bg = os.environ.get("WAKE_BACKGROUND_DIR") or os.path.join(D, "fma")
if not os.environ.get("WAKE_BACKGROUND_DIR") and not os.path.isdir(bg):
    z = os.path.join(D, "fma_small.zip")
    fetch("https://os.unil.cloud.switch.ch/fma/fma_small.zip", z)
    subprocess.run(["unzip", "-q", "-o", z, "-d", os.path.join(D, "fma_raw")], check=True)
    os.makedirs(bg, exist_ok=True)   # os.scandir does not recurse: flatten the mp3 tree into links
    for root, _, files in os.walk(os.path.join(D, "fma_raw")):
        for f in files:
            if f.endswith(".mp3"):
                link = os.path.join(bg, f)
                if not os.path.lexists(link): os.symlink(os.path.join(root, f), link)
print("  background clips:", len(os.listdir(bg)), flush=True)
PY
BG=${WAKE_BACKGROUND_DIR:-$DATA/fma}

# ── 5. openWakeWord's own trainer ───────────────────────────────────────────────
# openwakeword.train wants the clips in its four-directory layout and a yaml. We keep the brief's
# two directories as the truth and link a 90/10 train/test split into its layout.
"$PY" - <<'PY' || exit 1
import os, random
W = os.environ["W"]; OUT = os.path.join(W, "out", "hey_janus")
random.seed(7)
for src, pos in (("positives", "positive"), ("adversarial", "negative")):
    files = sorted(os.listdir(os.path.join(W, src))); random.shuffle(files)
    cut = int(len(files) * 0.9)
    for split, chunk in (("train", files[:cut]), ("test", files[cut:])):
        d = os.path.join(OUT, f"{pos}_{split}"); os.makedirs(d, exist_ok=True)
        for f in chunk:
            link = os.path.join(d, f)
            if not os.path.lexists(link): os.symlink(os.path.join(W, src, f), link)
        print(f"  {pos}_{split}: {len(chunk)}", flush=True)
PY

# openwakeword.train's __main__ imports piper-sample-generator unconditionally, even with
# --generate_clips off; piper_phonemize has no macOS wheel. Our positives come from Kokoro, so a
# stub that raises if anything ever calls it satisfies the import and nothing else.
mkdir -p "$W/piper-stub"
printf 'def generate_samples(*a, **k):\n    raise RuntimeError("positives come from Kokoro — see voice/wake/train.sh")\n' \
  > "$W/piper-stub/generate_samples.py"

cat > "$W/train.yml" <<EOF
target_phrase: ["$PHRASE"]
model_name: $MODEL
model_type: dnn
layer_size: 32
n_samples: 600
n_samples_val: 60
tts_batch_size: 50
custom_negative_phrases: []
piper_sample_generator_path: "$W/piper-stub"
output_dir: "$OUT"
rir_paths: ["$DATA/mit_rirs/16khz"]
background_paths: ["$BG"]
background_paths_duplication_rate: [1]
augmentation_rounds: 1
augmentation_batch_size: 16
feature_data_files: {"ACAV100M_sample": "$DATA/openwakeword_features_ACAV100M_2000_hrs_16bit.npy"}
false_positive_validation_data_path: "$DATA/validation_set_features.npy"
batch_n_per_class: {"ACAV100M_sample": 1024, "adversarial_negative": 50, "positive": 50}
steps: ${WAKE_STEPS:-50000}
max_negative_weight: 1500
target_false_positives_per_hour: 0.2
EOF

echo "### train: openwakeword.train --augment_clips --train_model (1-2 h of CPU)"
"$TPY" -m openwakeword.train --training_config "$W/train.yml" --augment_clips --train_model
# It exports the onnx and only then tries an onnx→tflite conversion that needs tensorflow 2.8.
# The model is already on disk by that point, so the model file — not the exit code — is the truth.
[ -s "$OUT/$MODEL.onnx" ] || { echo "### train: no $MODEL.onnx — see the traceback above"; exit 1; }
cp "$OUT/$MODEL.onnx" "$HERE/$MODEL.onnx"
echo "### done: $HERE/$MODEL.onnx"
echo "### next: bash voice/wake/accept.sh $HERE/$MODEL.onnx $W/hour.wav $W/ten.wav"
