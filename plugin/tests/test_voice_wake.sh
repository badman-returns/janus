#!/usr/bin/env bash
# The two rules that stop Janus answering himself. (1) `wake_threshold` — while he speaks, and for
# wake_settle after his last sound, the wake model has to be surer than 0.5, because his own tail
# scores over it; everywhere else 0.5 stands. (2) `false_alarm` — a turn with no real speech, or one
# whisper fills in with "Thank you." out of silence, writes no note, files nothing, and is one
# {"t": "false_alarm"} on the stream. Also the think watchdog's default: 120 s, the real concierge's
# answer takes 27-34. numpy and tmux are stubbed, so this needs neither voice/.venv nor a microphone.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; VOICE="$HERE/../../voice"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_voice_wake: $1"; exit 1; }
mkdir -p "$T/home" "$T/bin" "$T/mach/.delivery"
echo '{"project": "waketest"}' > "$T/mach/.delivery/config.json"      # no voice block: the defaults are what we test
printf '#!/usr/bin/env bash\ncase "$1" in list-windows) echo "@1 claude";; capture-pane) printf "\xe2\x9d\xaf \\n";; esac\nexit 0\n' > "$T/bin/tmux"
chmod +x "$T/bin/tmux"

cd "$T/mach" || fail "no machine dir"
HOME="$T/home" PATH="$T/bin:$PATH" VOICE="$VOICE" python3 - <<'PY' || fail "assertions failed (above)"
import os, sys, time, types
sys.modules.setdefault('numpy', types.ModuleType('numpy'))       # no audio is touched below
sys.path.insert(0, os.environ['VOICE'])
import loop, glob

# --- the knobs, as the fleet config leaves them ---
assert (loop.WAKE_HI, loop.WAKE_SETTLE, loop.MIN_SPEECH, loop.THINK_TIMEOUT) == (1.01, 1.5, 0.4, 120.0), \
    'defaults moved: %r' % ((loop.WAKE_HI, loop.WAKE_SETTLE, loop.MIN_SPEECH, loop.THINK_TIMEOUT),)

# --- the threshold is a function of the state and how long ago he stopped ---
assert loop.wake_threshold('speaking', 99.0) > 1, 'while he speaks the door is shut: no score can open it'
assert loop.wake_threshold('idle', 0.5) > 1, 'the tail is still his for wake_settle'
assert loop.wake_threshold('waiting', 1.49) > 1
assert loop.wake_threshold('idle', 1.51) == 0.5, 'the room goes back to the operator after wake_settle'
assert loop.wake_threshold('thinking', 600.0) == 0.5

# --- the false-alarm rule ---
assert loop.false_alarm('Thank you.', True) and loop.false_alarm(' THANKS! ', True)
assert loop.false_alarm('', True) and loop.false_alarm('what is waiting', False)   # nothing said, whatever came back
assert not loop.false_alarm('what is waiting', True)
assert not loop.false_alarm('thank you for the update', True)                      # only the bare phrase is junk

def turn(transcript, had_speech=True):
    """One listening turn end to end, with the transcriber stubbed. Returns the stream events."""
    loop.transcribe = lambda frames: transcript
    L.feed('key'); assert L.m.state == 'listening', L.m.state
    q = loop.stream.subscribe(); L.finish([], had_speech); loop.stream.unsubscribe(q)
    evs = []
    while not q.empty(): evs.append(q.get_nowait())
    return ''.join(evs)

L = loop.Loop()
evs = turn('Thank you.')
assert '"t": "false_alarm"' in evs, 'no false_alarm event: %r' % evs
assert '"final": true' not in evs, 'the phantom was shown as speech: %r' % evs
assert L.m.state == 'idle', 'a false alarm must leave the machine at rest, not %r' % L.m.state
assert not glob.glob('.delivery/inbox/note-*.txt'), 'a phantom turn wrote a note'

evs = turn('what is waiting', had_speech=False)     # the VAD never opened past min_speech
assert '"t": "false_alarm"' in evs and not glob.glob('.delivery/inbox/note-*.txt'), 'silence filed a note'

evs = turn('what is waiting')
assert '"t": "false_alarm"' not in evs, 'a real turn was called a false alarm'
assert '"text": "what is waiting", "final": true' in evs, evs
assert L.m.state == 'thinking', L.m.state
notes = glob.glob('.delivery/inbox/note-*.txt')
assert len(notes) == 1 and notes[0].endswith('-voice-what-is-waiting.txt'), notes
assert 'what is waiting' in open(notes[0]).read()
print('ok: thresholds 0.8/0.5, three false alarms filed nothing, the real turn filed one note')
PY
echo "PASS test_voice_wake"
