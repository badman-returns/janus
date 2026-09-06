#!/usr/bin/env bash
# type-line.sh types into a window only when its input box is empty; a draft means exit 3 and nothing typed;
# no visible input line means exit 2 and nothing typed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; TL="$HERE/../scripts/type-line.sh"
T=$(mktemp -d); export TMUX_SOCK="-L tl-$$"; trap 'tmux $TMUX_SOCK kill-server 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_type_line: $1"; exit 1; }
win(){ tmux $TMUX_SOCK list-windows -t tl -F '#{window_id}' | tail -1; }
# an idle Claude session: an empty input line; cat records whatever gets typed
tmux $TMUX_SOCK new-session -d -s tl -x 120 -y 20 "printf '❯ \n'; cat > '$T/typed'"
W=$(win); sleep 0.5
bash "$TL" "$W" "/dm process the pending items" || fail "empty box: exit $?"
sleep 0.5; grep -q '^/dm process the pending items$' "$T/typed" || fail "line not typed: $(cat "$T/typed")"
# a box holding an unsent line
tmux $TMUX_SOCK new-window -d -t tl "printf '❯ push it\n'; cat > '$T/typed2'"
W2=$(win); sleep 0.5
bash "$TL" "$W2" "/dm process" 2>"$T/err"; rc=$?
[ "$rc" = 3 ] || fail "draft: expected exit 3, got $rc"
grep -q 'push it' "$T/err" || fail "draft not named: $(cat "$T/err")"
sleep 0.3; [ ! -s "$T/typed2" ] || fail "typed over a draft: $(cat "$T/typed2")"
# no input line at all (a trust dialog, a menu)
tmux $TMUX_SOCK new-window -d -t tl "printf 'Do you trust the files in this folder?\n'; cat > '$T/typed3'"
W3=$(win); sleep 0.5
bash "$TL" "$W3" "/dm process" 2>/dev/null; rc=$?
[ "$rc" = 2 ] || fail "no prompt: expected exit 2, got $rc"
sleep 0.3; [ ! -s "$T/typed3" ] || fail "typed with no prompt"
echo "PASS test_type_line"
