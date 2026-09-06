#!/usr/bin/env bash
# dm-session.sh exports COGNEE_PLUGIN_DATASET from config memory_dataset (default: the project name).
set -u
export DM_BRIDGE=0   # isolated TMUX_SOCK already keeps bridge-link.sh off the real server; belt
                      # and suspenders so it never touches the operator's real `bridge` session.
HERE="$(cd "$(dirname "$0")" && pwd)"; DS="$HERE/../scripts/dm-session.sh"
T=$(mktemp -d); export TMUX_SOCK="-L md-$$"; trap 'tmux $TMUX_SOCK kill-server 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_memory_dataset: $1"; exit 1; }
mkdir -p "$T/p/.delivery" "$T/bin"; printf '#!/usr/bin/env bash\necho "$@" > "%s/claude-args"; env | grep COGNEE > "%s/claude-env"; sleep 60\n' "$T" "$T" > "$T/bin/claude"; chmod +x "$T/bin/claude"
echo '{"project":"p","services":{},"memory_dataset":"roomx"}' > "$T/p/.delivery/config.json"
tmux $TMUX_SOCK new-session -d -s dm-p -n control 'sleep 300'
(cd "$T/p" && DM_CLAUDE_BIN="$T/bin/claude" TMUX_SOCK="$TMUX_SOCK" bash "$DS" >/dev/null) || fail "dm-session exited $?"
waitenv(){ for i in $(seq 1 40); do [ -s "$T/claude-env" ] && return 0; sleep 0.25; done; return 1; }   # a fresh zsh takes seconds to start here
waitenv; grep -q 'COGNEE_PLUGIN_DATASET=roomx' "$T/claude-env" 2>/dev/null || fail "dataset not exported: $(cat "$T/claude-env" 2>/dev/null)"
echo '{"project":"p","services":{}}' > "$T/p/.delivery/config.json"; rm -f "$T/claude-env"
(cd "$T/p" && DM_CLAUDE_BIN="$T/bin/claude" TMUX_SOCK="$TMUX_SOCK" bash "$DS" >/dev/null) || fail "second dm-session exited $?"
waitenv; grep -q 'COGNEE_PLUGIN_DATASET=p' "$T/claude-env" 2>/dev/null || fail "default dataset not the project name"
kill $(pgrep -f "$T/bin/claude") 2>/dev/null   # stubs sleep 60; stop them now instead of waiting on kill-server
echo "PASS test_memory_dataset"
