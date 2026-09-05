#!/usr/bin/env bash
# The boundary check: a repo under a mapped path must commit as the mapped identity and run on the
# mapped Claude account. Prints nothing when clean; prints the fix and exits 1 otherwise.
set -uo pipefail
MAP="$HOME/.delivery-machine/identities.json"; [ -s "$MAP" ] || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
python3 - "$MAP" "$(git rev-parse --show-toplevel)" "$(git config user.name || true)" "$(git config user.email || true)" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" <<'EOF'
import json, os, sys
try: m = json.load(open(sys.argv[1]))
except Exception: sys.exit(0)   # a map we cannot read is not knowledge: stay silent, never accuse
top, name, email, cfg = os.path.realpath(sys.argv[2]), sys.argv[3], sys.argv[4], os.path.expanduser(sys.argv[5])
# Resolve both sides: a symlinked path (macOS /var, a symlinked home) must not silently skip the
# check, and matching on a full path segment keeps ~/code off ~/codebase.
res = {p: os.path.realpath(os.path.expanduser(p)).rstrip("/") for p in m}
hit = max((p for p in m if top == res[p] or top.startswith(res[p] + "/")), key=lambda p: len(res[p]), default=None)
if not hit: sys.exit(0)
want = m[hit]; problems = []
if not all(k in want for k in ("name", "email", "config_dir")): sys.exit(0)   # half-written entry: same
if name != want["name"] or email != want["email"]:
    problems.append(f'git identity is "{name} <{email}>", expected "{want["name"]} <{want["email"]}>":\n  git config --local user.name "{want["name"]}"\n  git config --local user.email "{want["email"]}"')
if os.path.realpath(cfg) != os.path.realpath(os.path.expanduser(want["config_dir"])):
    problems.append(f'Claude account is {cfg}, expected {want["config_dir"]} for this path:\n  restart this session with CLAUDE_CONFIG_DIR={want["config_dir"]} (dm.sh reads config.json claude_config_dir)')
if problems:
    print("IDENTITY MISMATCH in " + top); print("\n".join(problems)); sys.exit(1)
EOF
