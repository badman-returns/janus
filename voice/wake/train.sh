#!/usr/bin/env bash
# "hey Janus": render the training audio with Kokoro, then hand it to openWakeWord's own trainer.
# Five phases, each resumable — rerunning skips whatever is already on disk:
#   render → download gate → train venv → training data → openwakeword.train → voice/wake/hey_janus.onnx
#
#   bash voice/wake/train.sh                 render the audio, then stop at the gate with the sizes
#   WAKE_NEG_GB=8 WAKE_MAX_GB=12 bash voice/wake/train.sh   fit it on a Mac with ~15 GB free
#
# The full data set is 25.15 GB and this Mac has less. Two levers shrink it:
#   WAKE_NEG_GB (8)  download only the first N GB of openWakeWord's 17.28 GB negatives file and
#                    rewrite its .npy header to the whole rows that arrived (voice/wake/partial_npy.py).
#                    0, or anything past the full size, takes the whole file.
#   WAKE_SKIP_FMA    1 = background noise from ffmpeg instead of the 7.68 GB Free Music Archive;
#                    0 = insist on FMA. Unset means the gate decides: FMA if it fits the ceiling.
# Env: WAKE_MAX_GB (6) download ceiling; WAKE_SKIP_RENDER=1 the audio is already rendered;
#      WAKE_STEPS (50000) training steps; WAKE_BACKGROUND_DIR a directory of your own noise
#      audio, which beats both of the above.
# Nothing here belongs in git: every clip and every byte of data lives under ~/.brain/wake.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PY="$(dirname "$HERE")/.venv/bin/python"
export W="$HOME/.brain/wake" PHRASE="hey Janus"
DATA="$W/data"; OUT="$W/out"; TVENV="$W/venv-train"; MODEL=hey_janus
MAX_GB=${WAKE_MAX_GB:-6}; NEG_GB=${WAKE_NEG_GB:-8}
export HERE MAX_GB NEG_GB
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
# background music — 25.15 GB, more than this Mac has. Measure every byte before one lands, refuse
# over the ceiling, and say which of the two shrinking levers it picked.
echo "### gate: sizing openWakeWord's training data (ceiling ${MAX_GB} GB)"
GATE=$("$PY" - <<'PY'
import json, os, sys, urllib.request
def hf(repo, keep=lambda n: True):
    u = f"https://huggingface.co/api/datasets/{repo}?blobs=true"
    d = json.load(urllib.request.urlopen(u, timeout=90))
    return sum(s.get("size") or 0 for s in d["siblings"] if keep(s["rfilename"]))
def head(url):
    r = urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=90)
    return int(r.headers["content-length"])
MAX = float(os.environ["MAX_GB"]) * 1e9

# Only the prefix we will actually ask for counts — partial_npy.py takes a byte range and rewrites
# the .npy header to the whole rows that arrived, so a fraction of the file is still a valid array.
full = hf("davidscripka/openwakeword_features", lambda n: "ACAV100M" in n)
budget = int(float(os.environ["NEG_GB"]) * 1e9)
neg = full if budget <= 0 or budget >= full else budget
rows = [("openwakeword negatives (ACAV100M, 2000 h)" if neg == full else
         f"openwakeword negatives — first {neg/1e9:.2f} of {full/1e9:.2f} GB (WAKE_NEG_GB)", neg),
        ("openwakeword false-positive validation set", hf("davidscripka/openwakeword_features", lambda n: "validation" in n)),
        ("MIT environmental impulse responses", hf("davidscripka/MIT_environmental_impulse_responses"))]

# Background noise: the operator's own, the Free Music Archive, or ffmpeg's anoisesrc.
skip = os.environ.get("WAKE_SKIP_FMA", "")
if os.environ.get("WAKE_BACKGROUND_DIR"):
    mode, rows = "own", rows + [("background: WAKE_BACKGROUND_DIR, nothing to download", 0)]
elif skip == "1":
    mode, rows = "synthetic", rows + [("background: ffmpeg noise (WAKE_SKIP_FMA=1)", 0)]
else:
    fma = head("https://os.unil.cloud.switch.ch/fma/fma_small.zip")
    if skip == "0" or sum(n for _, n in rows) + fma <= MAX:
        mode, rows = "fma", rows + [("Free Music Archive small (background noise)", fma)]
    else:
        mode = "synthetic"
        rows += [(f"background: ffmpeg noise — FMA's {fma/1e9:.2f} GB does not fit the ceiling", 0)]
for name, n in rows:
    print(f"  {n/1e9:8.2f} GB  {name}", file=sys.stderr)
total = sum(n for _, n in rows)
print(f"  {total/1e9:8.2f} GB  TOTAL", file=sys.stderr)
print(f"{total/1e9:.2f} {mode}")
PY
) || { echo "gate: could not size the data (no network?)"; exit 1; }
read -r GB BGMODE <<<"$GATE"
[ -n "$GB" ] && awk -v g="$GB" 'BEGIN{exit !(g > 0)}' || { echo "gate: no size measured — not downloading blind"; exit 1; }
# Fails closed: only a measured total at or under the ceiling opens the gate.
if ! awk -v g="$GB" -v m="$MAX_GB" 'BEGIN{exit !(g <= m)}'; then
  cat <<EOF
### BLOCKED: openWakeWord's training data is ${GB} GB, over the ${MAX_GB} GB ceiling.
Nothing was downloaded. The rendered audio above is kept and the hey_jarvis stand-in keeps working.
To go ahead: raise WAKE_MAX_GB, lower WAKE_NEG_GB, or point WAKE_BACKGROUND_DIR at your own noise.
EOF
  exit 3
fi
echo "### gate: ${GB} GB, background = ${BGMODE}"

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

# Two packages pip does not pull in but this pipeline stops dead without, at opposite ends of it:
# torchaudio 2.9 dropped its own decoders and dispatches load() to TorchCodec, so every clip read in
# augment_clips raises; and torch 2.14's onnx exporter needs onnxscript, which only bites after the
# model has trained — an hour in, at the last line that matters.
"$TPY" -c "import torchcodec, onnxscript" 2>/dev/null || "$TVENV/bin/pip" install -q torchcodec onnxscript || exit 1

# acoustics 0.2.6 does `from scipy.special import sph_harm` at package-import time, for a
# spherical-harmonic helper openWakeWord never calls — it only wants acoustics.generator.noise.
# scipy removed that name in 1.15 (it is sph_harm_y now, with n/m and the angles the other way
# round), so importing openwakeword.data dies before a single clip is augmented. The venv is ours
# and disposable, so put the old name back in it. Idempotent: a rerun sees the shim and skips.
SITE="$("$TPY" -c "import sysconfig;print(sysconfig.get_paths()['purelib'])")"
ACO="$SITE/acoustics/directivity.py"
if [ -f "$ACO" ] && ! grep -q sph_harm_y "$ACO"; then
  sed -i '' 's|^from scipy.special import sph_harm  #.*|from scipy.special import sph_harm_y as _shy; sph_harm = lambda m, n, theta, phi: _shy(n, m, phi, theta)  # scipy >= 1.15 renamed it and swapped the arguments|' "$ACO"
  "$TPY" -c "import acoustics" || { echo "### deps: acoustics still will not import"; exit 1; }
  echo "### deps: patched acoustics for scipy $("$TPY" -c 'import scipy;print(scipy.__version__)')"
fi

# openWakeWord ships without its feature models: pip installs the code, and download_models() pulls
# melspectrogram.onnx and embedding_model.onnx afterwards. Without them the trainer dies before the
# first augmentation. voice/.venv already has them — copy, do not re-download, so the model we train
# sees byte-for-byte the same feature extractor the live loop will run it against.
TRES="$("$TPY" -c "import openwakeword, os; print(os.path.join(os.path.dirname(openwakeword.__file__), 'resources', 'models'))")"
if [ ! -s "$TRES/melspectrogram.onnx" ]; then
  LRES="$("$PY" -c "import openwakeword, os; print(os.path.join(os.path.dirname(openwakeword.__file__), 'resources', 'models'))")"
  mkdir -p "$TRES"
  cp "$LRES"/*.onnx "$TRES"/ || { echo "### deps: no feature models in $LRES"; exit 1; }
  echo "### deps: copied openwakeword feature models from the live venv"
fi

# torchaudio 2.9 removed info() along with its decoders. openwakeword.data calls it on every clip,
# RIR and background file, and so does torch_audiomentations.utils.io — ten call sites across two
# packages that are all satisfied by putting the one function back. soundfile is already installed
# and reads the same headers; only sample_rate and num_frames are ever read off the result.
TA="$SITE/torchaudio/__init__.py"
if [ -f "$TA" ] && ! grep -q "janus shim" "$TA"; then
  cat >> "$TA" <<'SHIM'


# --- janus shim ---------------------------------------------------------------
try:
    info
except NameError:
    import dataclasses as _dc
    import soundfile as _sf

    @_dc.dataclass
    class AudioMetaData:
        sample_rate: int
        num_frames: int
        num_channels: int
        bits_per_sample: int = 16
        encoding: str = "PCM_S"

    def info(uri, *_a, **_k):
        i = _sf.info(str(uri))
        return AudioMetaData(i.samplerate, i.frames, i.channels)
SHIM
  "$TPY" -c "import torchaudio; torchaudio.info" || { echo "### deps: torchaudio.info shim failed"; exit 1; }
  echo "### deps: shimmed torchaudio.info for torchaudio $("$TPY" -c 'import torchaudio;print(torchaudio.__version__)')"
fi

# openwakeword.train hands its training DataLoader num_workers=os.cpu_count()//2. On Linux those
# workers are forked and inherit the dataset; macOS spawns them, which pickles it — and the dataset
# holds mmap_batch_generator, whose label_transform_funcs are lambdas. Nothing about that is
# fixable from outside, and the workers buy little here: the generator only slices a memmap. So the
# loader runs in-process. (prefetch_factor goes with them — torch rejects it at num_workers=0.)
OWT="$SITE/openwakeword/train.py"
if grep -q "num_workers=n_cpus" "$OWT"; then
  sed -i '' 's|^\( *\)batch_size=None, num_workers=n_cpus, prefetch_factor=16)|\1batch_size=None)|' "$OWT"
  grep -q "num_workers=n_cpus" "$OWT" && { echo "### deps: could not patch the DataLoader"; exit 1; }
  echo "### deps: openwakeword DataLoader set to num_workers=0 (macOS spawns, and the dataset holds lambdas)"
fi

# ── 4. the data ─────────────────────────────────────────────────────────────────
echo "### data: → $DATA"
case "$BGMODE" in
  own) BG="$WAKE_BACKGROUND_DIR" ;;
  fma) BG="$DATA/fma" ;;
  *)   BG="$DATA/noise" ;;
esac
export BGMODE BG
NEG_BUDGET=$(awk -v g="$NEG_GB" 'BEGIN{printf "%d", g * 1e9}'); export NEG_BUDGET
"$TPY" - <<'PY' || exit 1
import os, subprocess, sys
sys.path.insert(0, os.environ["HERE"])
from huggingface_hub import snapshot_download
from partial_npy import fetch as fetch_npy      # a byte prefix, header rewritten to whole rows
D = os.path.join(os.environ["W"], "data")
HF = "https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main/"

def fetch(url, p):
    """curl, not urlretrieve: a download that dies must not leave a truncated file at the final
    name — a rerun would take it for complete and feed a corrupt .npy to the trainer. Downloads
    to .part, renames only on success."""
    if os.path.exists(p):
        return
    print(f"  {os.path.basename(p)} …", flush=True)
    subprocess.run(["curl", "-fL", "--retry", "5", "--retry-delay", "5", "-C", "-",
                    "-o", p + ".part", url], check=True)
    os.replace(p + ".part", p)

NEG = "openwakeword_features_ACAV100M_2000_hrs_16bit.npy"
fetch_npy(HF + NEG, os.path.join(D, NEG), int(os.environ["NEG_BUDGET"]))
fetch(HF + "validation_set_features.npy", os.path.join(D, "validation_set_features.npy"))
if not os.path.isdir(os.path.join(D, "mit_rirs", "16khz")):
    # openWakeWord scandirs rir_paths and hands every entry to a wav reader, so the config points at
    # the repo's 16khz/ subdirectory — the root also holds README.md and snapshot_download's .cache/.
    snapshot_download("davidscripka/MIT_environmental_impulse_responses",
                      repo_type="dataset", local_dir=os.path.join(D, "mit_rirs"))
bg = os.environ["BG"]
if os.environ["BGMODE"] == "fma" and not os.path.isdir(bg):
    z = os.path.join(D, "fma_small.zip")
    fetch("https://os.unil.cloud.switch.ch/fma/fma_small.zip", z)
    subprocess.run(["unzip", "-q", "-o", z, "-d", os.path.join(D, "fma_raw")], check=True)
    os.makedirs(bg, exist_ok=True)   # os.scandir does not recurse: flatten the mp3 tree into links
    for root, _, files in os.walk(os.path.join(D, "fma_raw")):
        for f in files:
            if f.endswith(".mp3"):
                link = os.path.join(bg, f)
                if not os.path.lexists(link): os.symlink(os.path.join(root, f), link)
PY

# Background noise without the 7.68 GB of music: 40 × 30 s of pink/brown/white noise at amplitudes
# 0.02-0.14, plus 30 s slices of hour.wav if the operator has recorded one. anoisesrc is a poor
# stand-in for a real room — a fan, a keyboard, a street, a television are what the model has to
# hear through. To swap it in: drop 16 kHz mono wavs into $DATA/noise (or point WAKE_BACKGROUND_DIR
# at a directory of your own), delete ~/.brain/wake/out/hey_janus/*_features_*.npy, and rerun.
if [ "$BGMODE" = synthetic ]; then
  mkdir -p "$BG"
  for i in $(seq 0 39); do
    f="$BG/anoise_$(printf %02d "$i").wav"; [ -s "$f" ] && continue
    c=$(echo "pink brown white" | cut -d' ' -f$(( i % 3 + 1 )))
    a=$(awk -v i="$i" 'BEGIN{printf "%.3f", 0.02 + 0.03 * (i % 5)}')
    ffmpeg -loglevel error -y -f lavfi -i "anoisesrc=c=$c:r=16000:a=$a:d=30:s=$i" \
      -ac 1 -c:a pcm_s16le "$f" || exit 1
  done
  if [ -s "$W/hour.wav" ] && ! ls "$BG"/room_000.wav >/dev/null 2>&1; then
    ffmpeg -loglevel error -y -i "$W/hour.wav" -ar 16000 -ac 1 -c:a pcm_s16le \
      -f segment -segment_time 30 "$BG/room_%03d.wav" || exit 1
  fi
fi
echo "  background clips: $(ls "$BG" | wc -l | tr -d ' ') in $BG"

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
"$TPY" -m openwakeword.train --training_config "$W/train.yml" --augment_clips --overwrite --train_model
# It exports the onnx and only then tries an onnx→tflite conversion that needs tensorflow 2.8.
# The model is already on disk by that point, so the model file — not the exit code — is the truth.
[ -s "$OUT/$MODEL.onnx" ] || { echo "### train: no $MODEL.onnx — see the traceback above"; exit 1; }
# torch 2.14's onnx exporter splits the weights into a <model>.onnx.data sidecar, so the .onnx
# alone is 14 KB of graph that onnxruntime refuses to load ("External data path does not exist").
# The whole model is 200 KB — inline it, so what ships is one file the fleet config can point at.
"$TPY" - <<PY || exit 1
import onnx
m = onnx.load("$OUT/$MODEL.onnx")                 # pulls the sidecar in, relative to its directory
onnx.save(m, "$HERE/$MODEL.onnx")                 # writes it back inline: one self-contained file
PY
echo "### done: $HERE/$MODEL.onnx"
echo "### next: bash voice/wake/accept.sh $HERE/$MODEL.onnx $W/hour.wav $W/ten.wav"
