#!/usr/bin/env bash
# state.py: name → listening → thinking → speaking; barge-in keeps the cursor and resumes; a question
# ends in waiting; dnd blocks the name and not the key; speak: yes and voice.on govern unsolicited speech.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 "$HERE/../../voice/state.py" --selftest || { echo "FAIL test_voice_state: selftest failed"; exit 1; }
echo "PASS test_voice_state"
