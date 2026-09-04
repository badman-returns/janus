#!/usr/bin/env bash
# knowledge-log.sh appends one line per write that lands on a knowledge path. The case it
# exists for is a write under a Claude config dir's memory/ — outside any git repo, so without
# this line there is no trace of it anywhere. Everything else must stay silent.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts/knowledge-log.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"; fail(){ echo "FAIL test_knowledge_log: $1"; exit 1; }
mkdir -p .delivery; echo '{"project":"t"}' > .delivery/config.json
K=.delivery/knowledge.log
w(){ printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" | bash "$S"; }
n(){ wc -l < $K 2>/dev/null | tr -d ' ' || echo 0; }

# defaults: .claude/knowledge/** and docs/decisions/**
w Write "$T/.claude/knowledge/atlas.md" || fail "exit $?"
[ -f $K ] || fail "no log written for a default knowledge path"
[ "$(n)" = 1 ] || fail "expected 1 line, got $(n)"
IFS=$'\t' read -r ts path kind < $K
case "$ts" in 20*T*Z) : ;; *) fail "ts not ISO-8601: '$ts'" ;; esac
[ "$path" = "$T/.claude/knowledge/atlas.md" ] || fail "path not logged verbatim: '$path'"
[ "$kind" = write ] || fail "Write should log 'write', got '$kind'"
[ "$(awk -F'\t' 'NF!=3' $K | wc -l | tr -d ' ')" = 0 ] || fail "line is not 3 tab-separated fields"

# Edit and NotebookEdit are edits; nested paths still match the ** glob
w Edit "$T/docs/decisions/0001-no-fork.md" >/dev/null
w NotebookEdit "$T/.claude/knowledge/deep/er/x.ipynb" >/dev/null
[ "$(n)" = 3 ] || fail "expected 3 lines, got $(n)"
[ "$(cut -f3 $K | tr '\n' ' ')" = "write edit edit " ] || fail "kinds wrong: $(cut -f3 $K | tr '\n' ' ')"

# a relative path (what a repo-relative glob is written for) matches too
w Write ".claude/knowledge/rel.md" >/dev/null
[ "$(n)" = 4 ] || fail "relative path did not match: $(cat $K)"

# anything else is silent
before=$(n)
w Write "$T/src/app/page.tsx" >/dev/null
w Write "$T/docs/design/REGISTER.md" >/dev/null
w Write "" >/dev/null
echo 'not json' | bash "$S" >/dev/null || fail "bad stdin exited $?"
[ "$(n)" = "$before" ] || fail "a non-knowledge write was logged: $(tail -3 $K)"

# config knowledge_paths replaces the defaults, and an absolute glob is honoured — the
# memory/ dir of a Claude config lives outside the repo, which is the real use case
: > $K
echo '{"project":"t","knowledge_paths":["'"$T"'/fakehome/.claude-x/projects/**/memory/**"]}' > .delivery/config.json
w Write "$T/fakehome/.claude-x/projects/-Users-t-work/memory/MEMORY.md" >/dev/null
[ "$(n)" = 1 ] || fail "absolute glob did not match: $(cat $K)"
w Write "$T/.claude/knowledge/atlas.md" >/dev/null
[ "$(n)" = 1 ] || fail "config replaced the defaults, so the default path must not match now"

# outside a Janus project: silent, and no file created anywhere
cd /; out=$(w Write "/tmp/.claude/knowledge/x.md") || fail "outside a project exited $?"
[ -z "$out" ] || fail "printed something outside a project: $out"

echo "PASS test_knowledge_log"
