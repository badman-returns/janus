#!/usr/bin/env bash
# Hook: turn a Claude question or permission prompt into a mission-control card,
# wait for the operator's answer from the web/phone, hand it back to Claude.
# No answer in time → say nothing, exit 0, the normal TUI prompt appears.
# Usage: ask.sh ask|permission   (hook JSON on stdin; run in the project root)
set -uo pipefail
[ -d .delivery ] || exit 0
MODE="$1"; IN=$(cat)
INBOX=".delivery/inbox"; mkdir -p "$INBOX"
# How long to hold the terminal waiting for a dashboard answer. 580s suits an operator who is
# away from the machine; at the keyboard it reads as a hang, because the TUI prompt cannot appear
# until this returns. So the default is short and the long wait is opt-in per project
# (config `ask_timeout`), which is the only place that knows whether anyone is sitting there.
CFG_TIMEOUT=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('ask_timeout') or '')" 2>/dev/null)
TIMEOUT=${DM_ASK_TIMEOUT:-${CFG_TIMEOUT:-45}}; POLL=${DM_ASK_POLL:-2}
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# no cockpit listening → nobody can answer a card; fall straight through to the terminal prompt
if [ -z "${DM_ASK_FORCE:-}" ]; then
  PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])" 2>/dev/null)
  PORT=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.delivery-machine/registry.json'))).get('$PROJ',{}).get('port') or '')" 2>/dev/null)
  [ -n "$PORT" ] && curl -s -m 1 -o /dev/null "http://localhost:$PORT/api/state" || exit 0
fi

# ---- card
CARD=$(DM_MODE="$MODE" DM_IN="$IN" python3 - <<'EOF'
import json, os, re, time
mode = os.environ["DM_MODE"]; h = json.loads(os.environ["DM_IN"] or "{}")
ti = h.get("tool_input") or {}
if mode == "ask":
    qs = [{"question": q.get("question",""), "options": [o.get("label","") for o in q.get("options",[])],
           "multi": bool(q.get("multiSelect"))} for q in ti.get("questions",[])]
    title = qs[0]["question"][:80] if qs else "Claude has a question"
else:
    frag = ti.get("command") or ti.get("file_path") or json.dumps(ti)[:120]
    title = f"Allow {h.get('tool_name','tool')}: {frag}"[:120]
    qs = [{"question": title, "options": ["Allow", "Deny"], "multi": False}]
slug = re.sub(r"[^a-z0-9-]+", "-", title.lower())[:40].strip("-") or "ask"
name = f"ask-{int(time.time()*1000)}-{slug}.txt"
open(os.path.join(".delivery/inbox", name), "w").write(json.dumps({"kind": mode, "title": title, "questions": qs}))
print(name); print(title)
EOF
)
NAME=$(echo "$CARD" | sed -n 1p); TITLE=$(echo "$CARD" | sed -n 2p)
[ -n "$NAME" ] || exit 0
bash "$PLUGIN_ROOT/scripts/notify.sh" "$( [ "$MODE" = ask ] && echo QUESTION || echo PERMISSION ): $TITLE" 2>/dev/null || true

# ---- wait for the dashboard's reply-<ts>-<slug(NAME)>.txt (it removes the ask file itself).
# Match on the ask's own ms timestamp: it survives the slug's 40-char cut and the .txt→-txt mangling.
KEY=$(echo "$NAME" | cut -d- -f1-2)
deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  R=$(ls "$INBOX" 2>/dev/null | grep "^reply-.*-${KEY}-" | head -1)
  if [ -n "$R" ]; then
    ANSWER=$(tail -n +2 "$INBOX/$R"); rm -f "$INBOX/$R" "$INBOX/$NAME"
    DM_MODE="$MODE" DM_ANS="$ANSWER" python3 - <<'EOF'
import json, os
mode, ans = os.environ["DM_MODE"], os.environ["DM_ANS"].strip()
if mode == "ask":
    out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
           "permissionDecisionReason": f"Operator answered from mission control: {ans}. Continue with this answer; do not ask again."}}
else:
    allow = ans.upper().startswith("ALLOW")
    d = {"behavior": "allow"} if allow else {"behavior": "deny", "message": f"Denied from mission control: {ans}"}
    out = {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": d}}
print(json.dumps(out))
EOF
    exit 0
  fi
  sleep "$POLL"
done
rm -f "$INBOX/$NAME"   # timed out: clear the card, let the TUI prompt take over
exit 0
