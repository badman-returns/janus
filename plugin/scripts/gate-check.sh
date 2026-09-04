#!/usr/bin/env bash
# PreToolUse hook (Write|Edit|NotebookEdit) — the scope gate. A task that quietly grows
# from one file to nine is the failure this catches: the threshold is re-checked on EVERY
# call against the accumulated set of files this session has touched (.delivery/.touched,
# cleared by session-start.sh), not once at the start. Touching a guarded file trips it
# immediately, whatever the count.
#
# Tripped and unapproved → a PreToolUse deny telling the agent to declare a checklist
# (checklist.sh) and get the operator to approve it. Approved → silence, forever after.
# Limits come from config.json "gate": {"max_files":4,"guarded":["run-log.sh",…]}.
#
# FAIL OPEN, always. Bad JSON, no python3, an unreadable config — exit 0 and let the write
# through, noting it in .delivery/pickup.log. A hook that blocks every edit when it breaks
# is worse than no hook: it would take the machine down and look like Claude being stuck.
# Usage: gate-check.sh   (hook JSON on stdin, run in the project root)
set -uo pipefail
[ -d .delivery ] || exit 0
DM_HOOK_JSON=$(cat); export DM_HOOK_JSON   # the heredoc owns stdin
OUT=$(python3 - 2>/dev/null <<'PY'
import fnmatch, json, os, sys, time

DEFAULT = {"max_files": 4, "guarded": ["run-log.sh", "proof-fresh.sh", "hooks.json"]}
TOUCHED = ".delivery/.touched"

def approved_for_current_slice():
    """The current slice is the one the ledger last spoke about — that is the only record
    of what is in flight. With no ledger there is no current slice, so any approved
    checklist counts; otherwise a project that never logs a run could not unblock itself."""
    d = ".delivery/checklist"
    if not os.path.isdir(d):
        return False
    names = None
    try:
        with open(".delivery/runs.jsonl") as f:
            last = [l for l in f if l.strip()][-1]
        s = json.loads(last).get("slice")
        if s:
            names = [f"{s}.json"]
    except Exception:
        pass
    if names is None:
        names = os.listdir(d)
    for n in names:
        try:
            if json.load(open(os.path.join(d, n))).get("approved_at"):
                return True
        except Exception:
            continue
    return False

def main():
    h = json.loads(os.environ.get("DM_HOOK_JSON") or "{}")
    p = (h.get("tool_input") or {}).get("file_path") or ""
    if not p:
        return
    touched = []
    try:
        touched = [l.strip() for l in open(TOUCHED) if l.strip()]
    except OSError:
        pass
    if p not in touched:
        touched.append(p)
        with open(TOUCHED, "a") as f:
            f.write(p + "\n")

    # Read the config AFTER recording the touch, and without a fallback: an unreadable
    # config.json means we do not know this project's intent, so the outer handler fails
    # open — but the count is already on disk, so the gate works again once it is fixed.
    cfg = json.load(open(".delivery/config.json"))

    # OPT-IN: no "gate" key means off, and so does `"gate": false`. A mechanism that refuses an
    # agent's edits must never switch itself on because someone upgraded the plugin — a project
    # mid-flight would start being denied at its fifth file, against limits nobody there chose.
    # dm-init writes the key, so new projects get it; existing ones adopt it deliberately.
    if "gate" not in cfg or cfg["gate"] is False or cfg["gate"] is None:
        sys.exit(0)
    gate = cfg["gate"] if isinstance(cfg["gate"], dict) else {}
    max_files = int(gate.get("max_files", DEFAULT["max_files"]))
    guarded = gate.get("guarded", DEFAULT["guarded"])
    if max_files <= 0 and not guarded:
        sys.exit(0)

    base = os.path.basename(p)
    hit = next((g for g in guarded
                if fnmatch.fnmatch(p, g) or fnmatch.fnmatch(base, g) or fnmatch.fnmatch(p, "*/" + g)), None)
    if hit:
        why = f"{p} is a guarded file (gate.guarded matched {hit!r})"
    elif len(touched) > max_files:
        why = f"this task has now touched {len(touched)} files, past the gate of {max_files}"
    else:
        return
    if approved_for_current_slice():
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Janus scope gate: {why}. Declare what you are doing before going further — "
            "`checklist.sh init <slice> '<intent>' '<trigger>'`, then `checklist.sh add <slice> "
            "'<what will be done>' '<what will prove it>'` for each item — and ask the operator to "
            "approve it (`checklist.sh approve <slice>`, or a gate in .delivery/inbox). "
            "Re-try this edit once the checklist is approved.")}}))

try:
    main()
except Exception as e:
    try:
        with open(".delivery/pickup.log", "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} — gate-check failed open: {e!r}\n")
    except Exception:
        pass
PY
) || exit 0
[ -n "$OUT" ] && printf '%s\n' "$OUT"
exit 0
