#!/usr/bin/env bash
# is-live.sh: heartbeat younger than window → live; older → not; claude window → live.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/is-live.sh"
T=$(mktemp -d); trap 'rm -rf "$T"; tmux kill-session -t dm-livetest 2>/dev/null' EXIT
mkdir -p "$T/.delivery/agents"; echo '{"project":"livetest","services":{}}' > "$T/.delivery/config.json"
cd "$T"
fail(){ echo "FAIL test_is_live: $1"; exit 1; }

bash "$S" && fail "empty project reported live"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "{\"sid\":\"a\",\"ts\":\"$now\"}" > .delivery/agents/a.json
bash "$S" || fail "fresh heartbeat not live"
old=$(python3 -c "import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=300)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
echo "{\"sid\":\"a\",\"ts\":\"$old\"}" > .delivery/agents/a.json
bash "$S" && fail "5-minute-old heartbeat reported live"
tmux new-session -d -s dm-livetest -n claude 'sleep 30'
bash "$S" || fail "claude tmux window not live"
echo "PASS test_is_live"
