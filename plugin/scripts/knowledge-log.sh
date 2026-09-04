#!/usr/bin/env bash
# PostToolUse hook (Write|Edit|NotebookEdit) — append one line to .delivery/knowledge.log
# for every write that lands on a knowledge path. A write under a Claude config dir's
# memory/ is outside any git repo, so without this it leaves no trace at all.
#
# Which paths count comes from config.json "knowledge_paths" (globs, absolute ones and ~
# allowed); absent, the default is .claude/knowledge/** and docs/decisions/**.
# Silent no-op outside a Janus project, on a non-match, and on any internal error.
# Usage: knowledge-log.sh   (hook JSON on stdin, run in the project root)
set -uo pipefail
[ -d .delivery ] || exit 0
# the heredoc owns stdin, so read the payload off it first
DM_HOOK_JSON=$(cat); export DM_HOOK_JSON
python3 - <<'PY' 2>/dev/null || exit 0
import fnmatch, json, os, time

DEFAULT = [".claude/knowledge/**", "docs/decisions/**"]
h = json.loads(os.environ.get("DM_HOOK_JSON") or "{}")
p = (h.get("tool_input") or {}).get("file_path") or ""
if not p:
    raise SystemExit(0)
try:
    pats = json.load(open(".delivery/config.json")).get("knowledge_paths") or DEFAULT
except Exception:
    pats = DEFAULT

# A hook reports an absolute path; the globs people write are usually repo-relative, so try
# both. realpath on both sides on purpose: on macOS the shell's cwd is /var/... while
# os.getcwd() is /private/var/..., and a relpath across that symlink comes back as ../../..
rp = os.path.realpath(p)
cands = [p, rp]
try:
    cands.append(os.path.relpath(rp, os.path.realpath(os.getcwd())))
except ValueError:
    pass
if not any(fnmatch.fnmatch(c, os.path.expanduser(pat)) for c in cands for pat in pats):
    raise SystemExit(0)

kind = "write" if (h.get("tool_name") or "") == "Write" else "edit"
ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
with open(".delivery/knowledge.log", "a") as f:
    f.write(f"{ts}\t{p}\t{kind}\n")
PY
exit 0
