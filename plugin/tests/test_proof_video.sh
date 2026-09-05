#!/usr/bin/env bash
# proof-video.sh: two still scenes + two narration lines -> proof.mp4 with video+audio, an srt with 2 cues.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; PV="$HERE/../scripts/proof-video.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_proof_video: $1"; exit 1; }
command -v ffmpeg >/dev/null || { echo "PASS test_proof_video (skipped: no ffmpeg)"; exit 0; }
mkdir -p "$T/proof/s/scenes"; cd "$T"
ffmpeg -loglevel error -f lavfi -i color=c=blue:s=640x360:d=1 -frames:v 1 proof/s/scenes/01-login.png
ffmpeg -loglevel error -f lavfi -i color=c=green:s=640x360:d=1 -frames:v 1 proof/s/scenes/02-desk.png
printf 'The receptionist signs in with an OTP.\nThe desk shows the freed slot.\n' > proof/s/narration.md
PROOF_VIDEO_TTS=none bash "$PV" s >/dev/null || fail "exited $?"   # stderr stays, so a failure still says why
[ -s proof/s/proof.mp4 ] || fail "no proof.mp4"
ffprobe -v error -select_streams v -show_entries stream=codec_name,width -of csv=p=0 proof/s/proof.mp4 | grep -q 'h264,1280' || fail "video stream not h264 1280"
ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 proof/s/proof.mp4 | grep -q 'aac' || fail "no aac audio track"
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 proof/s/proof.mp4 | cut -d. -f1); [ "$D" -ge 7 ] || fail "duration $D s, expected >= 8 (2 scenes x 4 s)"
[ "$(grep -c ' --> ' proof/s/proof.srt)" = 2 ] || fail "srt cues: $(grep -c ' --> ' proof/s/proof.srt)"
grep -q 'The desk shows the freed slot' proof/s/proof.srt || fail "caption text missing"
echo "PASS test_proof_video"
