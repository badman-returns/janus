#!/usr/bin/env bash
# Hook: append one activity line + refresh this session's heartbeat, so the
# dashboard can show what EACH live session/agent is doing. Silent no-op
# outside a dm project. Usage: activity.sh <EventLabel>  (hook JSON on stdin)
set -uo pipefail
[ -d .delivery ] || exit 0
# the heredoc below OWNS stdin, so the hook payload must be read off it first —
# json.load(sys.stdin) inside would parse this script, not the event
DM_HOOK_JSON=$(cat) DM_EVENT="$1" python3 - <<'EOF' 2>/dev/null
import json, time, os
event = os.environ.get("DM_EVENT", "")
try: h = json.loads(os.environ.get("DM_HOOK_JSON") or "{}")
except Exception: h = {}

sid = (h.get("session_id") or "main")[:8]
cwd = h.get("cwd") or os.getcwd()
detail = ""
role = "session"
if event == "prompt":
    detail = (h.get("prompt") or "")[:120]
elif event == "tool":
    ti = h.get("tool_input") or {}
    tn = h.get("tool_name") or "?"
    frag = ti.get("command") or ti.get("file_path") or ti.get("description") or ti.get("prompt") or ""
    detail = tn + (": " + str(frag)[:90] if frag else "")
    if tn in ("Task", "Agent"):
        role = "spawning agent"
        detail = "→ " + (ti.get("description") or ti.get("subagent_type") or "agent")
elif event == "agent-done":
    detail = "subagent finished"
elif event == "stop":
    detail = "turn finished"

ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
line = json.dumps({"ts": ts, "event": event, "detail": detail, "sid": sid})

# 1) shared activity stream (capped)
p = ".delivery/activity.jsonl"
with open(p, "a") as f: f.write(line + "\n")
try:
    with open(p) as f: lines = f.readlines()
    if len(lines) > 1200:
        with open(p, "w") as f: f.writelines(lines[-600:])
except Exception: pass

# 2) per-session heartbeat — one file per live session/agent
os.makedirs(".delivery/agents", exist_ok=True)
hb = {"sid": sid, "ts": ts, "event": event, "detail": detail, "role": role, "cwd": os.path.basename(cwd)}
with open(f".delivery/agents/{sid}.json", "w") as f: json.dump(hb, f)

# 3) sweep heartbeats older than 30 min
cutoff = time.time() - 1800
for fn in os.listdir(".delivery/agents"):
    fp = os.path.join(".delivery/agents", fn)
    try:
        if os.path.getmtime(fp) < cutoff: os.remove(fp)
    except Exception: pass
EOF
exit 0
