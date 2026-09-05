#!/usr/bin/env bash
# speech.py turns reply markdown into spoken sentences and reads the optional header lines.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 "$HERE/../../voice/speech.py" --selftest || { echo "FAIL test_voice_speech: selftest failed"; exit 1; }
echo "PASS test_voice_speech"
