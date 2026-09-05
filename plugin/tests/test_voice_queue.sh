#!/usr/bin/env bash
# voice-say.sh: speaks queued lines in order, one process at a time, only when voice.on exists and dnd
# does not — and never over the front door's own voice: while the loop's /state reports speaking the
# queue waits, and goes as soon as it reads idle. A loop that is not running never blocks the desk.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; VS="$HERE/../scripts/voice-say.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_voice_queue: $1"; exit 1; }
mkdir -p "$T/home/.brain/voice-queue" "$T/bin"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/spoken"; sleep 0.2\n' "$T" > "$T/bin/say"; chmod +x "$T/bin/say"
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"; chmod +x "$T/bin/curl"   # front door not running
run(){ HOME="$T/home" PATH="$T/bin:$PATH" SAY_BIN="$T/bin/say" bash "$VS" "$@"; }
echo "clinic-app: verifier passed slice 4" > "$T/home/.brain/voice-queue/1000.txt"
echo "platform-app: gate one waiting" > "$T/home/.brain/voice-queue/1001.txt"
run --once || fail "exited $?"
[ ! -e "$T/spoken" ] || fail "spoke while voice.on absent"
touch "$T/home/.brain/voice.on"; touch "$T/home/.brain/dnd"
run --once || fail "exited $?"
[ ! -e "$T/spoken" ] || fail "spoke during dnd"
rm "$T/home/.brain/dnd"
run --once || fail "exited $?"
[ "$(wc -l < "$T/spoken" | tr -d ' ')" = 2 ] || fail "expected 2 utterances: $(cat "$T/spoken")"
sed -n 1p "$T/spoken" | grep -q '^clinic-app: verifier passed slice 4$' || fail "order or prefix wrong: $(sed -n 1p "$T/spoken")"
[ -z "$(ls "$T/home/.brain/voice-queue")" ] || fail "queue not drained"
# Two voices never overlap at the desk: while /state says speaking the line waits; on idle it speaks.
printf '#!/usr/bin/env bash\ncat "%s/state.json"\n' "$T" > "$T/bin/curl"; chmod +x "$T/bin/curl"
echo '{"t":"state","state":"speaking"}' > "$T/state.json"
rm -f "$T/spoken"; echo "brain: gate two waiting" > "$T/home/.brain/voice-queue/1002.txt"
run --once & pid=$!
sleep 3
[ ! -e "$T/spoken" ] || fail "spoke over the front door: $(cat "$T/spoken")"
echo '{"t":"state","state":"idle"}' > "$T/state.json"
wait "$pid" || fail "waiting pass exited $?"
grep -q '^brain: gate two waiting$' "$T/spoken" 2>/dev/null || fail "silent after the loop went idle: $(cat "$T/spoken" 2>/dev/null)"
echo "PASS test_voice_queue"
