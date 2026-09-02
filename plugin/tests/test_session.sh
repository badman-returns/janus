#!/usr/bin/env bash
# dm-session.sh: names windows claude, claude-2…; passes args; exports CLAUDE_CONFIG_DIR from config.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/dm-session.sh"
T=$(mktemp -d); trap 'rm -rf "$T"; tmux kill-session -t dm-sesstest 2>/dev/null' EXIT
mkdir -p "$T/.delivery"; echo '{"project":"sesstest","services":{},"claude_config_dir":"~/.claude-fake"}' > "$T/.delivery/config.json"
cat > "$T/fakeclaude" <<'EOF'
#!/usr/bin/env bash
echo "ARGS=$* CFG=${CLAUDE_CONFIG_DIR:-}" > "$(dirname "$0")/out-$1"; sleep 30
EOF
chmod +x "$T/fakeclaude"; cd "$T"; fail(){ echo "FAIL test_session: $1"; exit 1; }
tmux new-session -d -s dm-sesstest -n control 'sleep 60'
w1=$(DM_CLAUDE_BIN="$T/fakeclaude" bash "$S" one); [ "$w1" = "claude" ] || fail "first window named $w1"
w2=$(DM_CLAUDE_BIN="$T/fakeclaude" bash "$S" two --resume abc); [ "$w2" = "claude-2" ] || fail "second window named $w2"
for i in 1 2 3 4 5 6 7 8 9 10; do [ -f out-two ] && break; sleep 0.5; done   # shell init in the new window takes a moment
grep -q "ARGS=two --resume abc CFG=$HOME/.claude-fake" out-two || fail "args/config dir not passed: $(cat out-two 2>/dev/null)"
tmux list-windows -t dm-sesstest -F '#W' | grep -qx claude-2 || fail "window claude-2 missing"
echo "PASS test_session"
