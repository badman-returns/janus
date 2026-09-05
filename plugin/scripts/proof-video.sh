#!/usr/bin/env bash
# Assemble proof/<slice>/proof.mp4 from scenes + narration.md.
#  scenes/NN-name.webm  Playwright recordings, one per checklist proof item
#  scenes/NN-name.png   still frames, shown for 4 s (API-only slices render terminal text to PNG)
#  narration.md         one sentence per scene, same order; spoken through voice/tts.sh (Kokoro,
#                       with its own `say` fallback) and burned in as captions, also kept as proof.srt
# Env: PROOF_VIDEO_TTS=none  -> silent AAC track (tests, or no voice);
#      PROOF_VIDEO_VOICE     -> voice name (default: the machine's config voice.kokoro_voice, else am_michael)
# Usage: proof-video.sh <slice>   (from the machine root; honours config proof_dir)
set -euo pipefail
SLICE=${1:?slice}
HERE=$(cd "$(dirname "$0")" && pwd); PLUG=$(cd "$HERE/.." && pwd); TTS="$PLUG/../voice/tts.sh"
PROOF=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('proof_dir') or 'proof')" 2>/dev/null || echo proof)
D="$PROOF/$SLICE"; S="$D/scenes"; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
[ -d "$S" ] || { echo "no $S" >&2; exit 2; }
[ -s "$D/narration.md" ] || { echo "no $D/narration.md" >&2; exit 2; }
LINES=(); SCENES=()   # bash 3.2: no mapfile
while IFS= read -r l; do LINES+=("$l"); done < <(grep -v '^[[:space:]]*$' "$D/narration.md")
while IFS= read -r l; do SCENES+=("$l"); done < <(ls "$S" | grep -E '\.(webm|mp4|png)$' | sort)
[ "${#LINES[@]}" = "${#SCENES[@]}" ] || { echo "narration has ${#LINES[@]} lines, scenes has ${#SCENES[@]} files — one line per scene" >&2; exit 2; }
VOICE=${PROOF_VIDEO_VOICE:-$(python3 -c "import json;print((json.load(open('.delivery/config.json')).get('voice') or {}).get('kokoro_voice') or 'am_michael')" 2>/dev/null || echo am_michael)}
T0=0; : > "$W/list.txt"; : > "$D/proof.srt"
ts(){ python3 -c "import sys;s=float(sys.argv[1]);print('%02d:%02d:%06.3f'%(s//3600,(s%3600)//60,s%60))" "$1" | tr . ,; }
for i in "${!SCENES[@]}"; do
  f="$S/${SCENES[$i]}"; line="${LINES[$i]}"; n=$(printf %02d $((i+1)))
  if [ "${PROOF_VIDEO_TTS:-tts}" != none ] && [ -s "$TTS" ] && bash "$TTS" "$line" "$W/$n.wav" "$VOICE" >/dev/null && [ -s "$W/$n.wav" ]; then
    ffmpeg -loglevel error -y -i "$W/$n.wav" -ar 24000 -ac 1 -c:a aac -b:a 96k "$W/$n.m4a"
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$W/$n.m4a")
  else   # same rate and layout as the spoken track: concat wants every scene shaped alike
    dur=4; ffmpeg -loglevel error -y -f lavfi -i anullsrc=r=24000:cl=mono -t "$dur" -c:a aac "$W/$n.m4a"
  fi
  case "$f" in
    # apad in both: a scene is never cut to the narration's length — the still holds its 4 s, the
    # recording plays to its end, and the silence stretches to meet it
    *.png) vdur=$(python3 -c "print(max(4.0, float('$dur')+0.5))"); ffmpeg -loglevel error -y -loop 1 -i "$f" -i "$W/$n.m4a" -t "$vdur" -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black,fps=25" -af apad -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$W/$n.mp4" ;;
    *)     ffmpeg -loglevel error -y -i "$f" -i "$W/$n.m4a" -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black,fps=25" -af apad -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$W/$n.mp4" ;;
  esac
  printf "file '%s'\n" "$W/$n.mp4" >> "$W/list.txt"
  vdur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$W/$n.mp4")   # the cue follows the cut, not the plan
  T1=$(python3 -c "print(float('$T0')+float('$vdur'))")
  printf '%d\n%s --> %s\n%s\n\n' $((i+1)) "$(ts "$T0")" "$(ts "$T1")" "$line" >> "$D/proof.srt"; T0=$T1
done
ffmpeg -loglevel error -y -f concat -safe 0 -i "$W/list.txt" -vf "subtitles=$D/proof.srt:force_style='FontSize=18,Outline=1,MarginV=28'" -c:v libx264 -preset veryfast -crf 24 -pix_fmt yuv420p -c:a aac "$D/proof.mp4" \
  || ffmpeg -loglevel error -y -f concat -safe 0 -i "$W/list.txt" -c copy "$D/proof.mp4"   # no libass: captions stay in proof.srt
SZ=$(stat -f%z "$D/proof.mp4"); if [ "$SZ" -gt $((50*1024*1024)) ]; then ffmpeg -loglevel error -y -i "$D/proof.mp4" -vf scale=960:540 -c:v libx264 -crf 28 -c:a copy "$W/small.mp4" && mv "$W/small.mp4" "$D/proof.mp4"; fi
echo "$D/proof.mp4 ($(stat -f%z "$D/proof.mp4") bytes, $(grep -c ' --> ' "$D/proof.srt") scenes)"
