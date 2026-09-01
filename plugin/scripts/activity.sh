#!/usr/bin/env bash
# Hook: append one activity line per session event so the dashboard can show
# what the Claude session is doing, live. Silent no-op outside a dm project.
# Usage (from hooks.json): activity.sh <EventLabel>   (hook JSON arrives on stdin)
set -uo pipefail
[ -d .delivery ] || exit 0
python3 - "$1" <<'EOF' 2>/dev/null
import json, sys, time, os
event = sys.argv[1]
try: h = json.load(sys.stdin)
except Exception: h = {}
detail = ""
if event == "prompt":
    detail = (h.get("prompt") or "")[:120]
elif event == "tool":
    ti = h.get("tool_input") or {}
    frag = ti.get("command") or ti.get("file_path") or ti.get("description") or ti.get("prompt") or ""
    detail = (h.get("tool_name") or "?") + (": " + str(frag)[:90] if frag else "")
elif event == "agent-done":
    detail = "subagent finished"
elif event == "stop":
    detail = "turn finished"
line = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                   "event": event, "detail": detail})
p = ".delivery/activity.jsonl"
with open(p, "a") as f: f.write(line + "\n")
# cap the file so it never grows unbounded
try:
    with open(p) as f: lines = f.readlines()
    if len(lines) > 1200:
        with open(p, "w") as f: f.writelines(lines[-600:])
except Exception: pass
EOF
exit 0
