#!/usr/bin/env bash
# ttyd-run.sh: restarts its child when leaked pty masters exceed the soft cap and no client is connected.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/ttyd-run.sh"
T=$(mktemp -d); trap 'rm -rf "$T"; kill $W 2>/dev/null; pkill -f "$T/ttyd" 2>/dev/null' EXIT
fail(){ echo "FAIL test_ttyd_run: $1"; exit 1; }
# a fake ttyd that holds two pty masters and never exits on its own
cat > "$T/ttyd" <<'EOF'
#!/usr/bin/env bash
echo "fake ttyd up $$" >> "$(dirname "$0")/log"
exec python3 -c "import os,time;[os.open('/dev/ptmx',os.O_RDWR) for _ in range(2)];time.sleep(60)"
EOF
chmod +x "$T/ttyd"
PATH="$T:$PATH" DM_TTYD_SOFT=1 DM_TTYD_POLL=1 bash "$S" --whatever > "$T/out" 2>&1 & W=$!; disown $W
starts(){ grep -c 'fake ttyd up' "$T/log" 2>/dev/null || echo 0; }
for i in $(seq 1 16); do [ "$(starts)" -ge 2 ] && break; sleep 0.5; done
[ "$(starts)" -ge 2 ] || fail "child was not restarted: $(cat "$T/out")"
grep -q "restarting to free them" "$T/out" || fail "no restart log line: $(cat "$T/out")"
echo "PASS test_ttyd_run"
