#!/usr/bin/env bash
# The seat column: fleet-status.sh says which account each machine sits on, read only from that
# machine's .delivery/config.json claude_config_dir — office for ~/.claude-alt, personal otherwise.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; FS="$HERE/../scripts/fleet-status.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_fleet_seat: $1"; exit 1; }
mkdir -p "$T/home/.delivery-machine" "$T/web/.delivery" "$T/brain/.delivery" "$T/bare/.delivery"
echo '{"project":"web","services":{},"claude_config_dir":"~/.claude-alt"}' > "$T/web/.delivery/config.json"
echo '{"project":"brain","services":{},"claude_config_dir":"~/.claude-tsg"}' > "$T/brain/.delivery/config.json"
echo '{"project":"bare","services":{}}' > "$T/bare/.delivery/config.json"
cat > "$T/home/.delivery-machine/registry.json" <<EOF
{"web":{"dir":"$T/web","session":"dm-web","port":1,"ttyd_port":2,"started":"x"},
 "brain":{"dir":"$T/brain","session":"dm-brain","port":3,"ttyd_port":4,"started":"x"},
 "bare":{"dir":"$T/bare","session":"dm-bare","port":5,"ttyd_port":6,"started":"x"}}
EOF
OUT=$(HOME="$T/home" bash "$FS") || fail "status exited $?"
[ "$(echo "$OUT" | grep -c .)" = 3 ] || fail "expected one line per machine: $OUT"
echo "$OUT" | grep -q '^web · office · ' || fail "office seat missing: $OUT"
echo "$OUT" | grep -q '^brain · personal · ' || fail "personal seat missing: $OUT"
echo "$OUT" | grep -q '^bare · personal · ' || fail "no claude_config_dir should read personal: $OUT"
[ "$(echo "$OUT" | grep -c office)" = 1 ] || fail "only the alt machine is on the office seat: $OUT"
echo "PASS test_fleet_seat"
