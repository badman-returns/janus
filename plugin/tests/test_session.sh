#!/usr/bin/env bash
# dm-session.sh: names windows claude@<project>, claude-2@<project>…; passes args; exports
# CLAUDE_CONFIG_DIR from config. The project is in the name so the Telegram bridge (which names a
# topic after the window) gets one topic per machine — so the name is asserted here, and so is
# every consumer that must still find the window: the watcher's by-id lookup and tmux's own
# prefix match on `dm-<project>:claude` (what the concierge skill captures panes with).
set -u
export DM_BRIDGE=0   # this test drives dm-session.sh on the REAL tmux server; keep bridge-link.sh
                     # out of it, or the suite links the operator's live claude windows into
                     # a `bridge` session. test_bridge_link.sh covers the real behaviour on its
                     # own isolated server.
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/dm-session.sh"
T=$(mktemp -d); trap 'rm -rf "$T"; tmux kill-session -t dm-sesstest 2>/dev/null' EXIT
mkdir -p "$T/.delivery"; echo '{"project":"sesstest","services":{},"claude_config_dir":"~/.claude-fake"}' > "$T/.delivery/config.json"
cat > "$T/fakeclaude" <<'EOF'
#!/usr/bin/env bash
echo "ARGS=$* CFG=${CLAUDE_CONFIG_DIR:-}" > "$(dirname "$0")/out-$1"; sleep 30
EOF
chmod +x "$T/fakeclaude"; cd "$T"; fail(){ echo "FAIL test_session: $1"; exit 1; }
tmux new-session -d -s dm-sesstest -n control 'sleep 60'
w1=$(DM_CLAUDE_BIN="$T/fakeclaude" bash "$S" one); [ "$w1" = "claude@sesstest" ] || fail "first window named $w1"
# tmux resolves an unambiguous prefix, so `dm-<project>:claude` still names the one session window
# (what the concierge skill captures panes with). A SECOND session makes that prefix ambiguous —
# it always did name only the first window, and now it names none; nothing but that skill uses it.
tmux capture-pane -p -t dm-sesstest:claude >/dev/null 2>&1 || fail "dm-sesstest:claude no longer resolves"
w2=$(DM_CLAUDE_BIN="$T/fakeclaude" bash "$S" two --resume abc); [ "$w2" = "claude-2@sesstest" ] || fail "second window named $w2"
for i in 1 2 3 4 5 6 7 8 9 10; do [ -f out-two ] && break; sleep 0.5; done   # shell init in the new window takes a moment
grep -q "ARGS=two --resume abc CFG=$HOME/.claude-fake" out-two || fail "args/config dir not passed: $(cat out-two 2>/dev/null)"
tmux list-windows -t dm-sesstest -F '#W' | grep -qx 'claude-2@sesstest' || fail "window claude-2@sesstest missing"

# the watcher types into the session by window id, found with a prefix match on the name — the
# only way it can reach a window whose name is now claude@<project> (and the only safe way when
# the bridge has the same window linked twice)
LIVEWIN=$(tmux list-windows -t dm-sesstest -F '#{window_id} #W' | awk '$2 ~ /^claude/ {print $1; exit}')
[ -n "$LIVEWIN" ] || fail "watcher's selector found no claude window"
[ "$(tmux display-message -p -t "$LIVEWIN" '#W')" = "claude@sesstest" ] || fail "watcher's id points elsewhere: $LIVEWIN"
grep -q '\$2 ~ /\^claude/' "$HERE/../scripts/watch.sh" || fail "watch.sh no longer selects by the claude prefix"
echo "PASS test_session"
