#!/usr/bin/env bash
# Stop this project's machine deliberately, and say so in the registry — the counterpart to
# orchestrator.sh. `tmux kill-session` alone leaves the fleet registry claiming the machine is
# running, so after a reboot the fleet page (and dm-boot.sh) cannot tell a machine somebody
# switched off from one that died.
#
#   dm-stop.sh            handoff, stop services, kill the session, mark it "stopped"
#   dm-stop.sh --pause    handoff, stop services, KEEP the session, mark it "paused"
#
# The registry entry is never deleted: the fleet page needs it, and starting the machine again
# (orchestrator.sh) rewrites the entry and so clears the state by itself.
# Usage: from the project root.
set -uo pipefail
[ -f .delivery/config.json ] || { echo "no .delivery/config.json — not a Janus project"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE=stopped; [ "${1:-}" = "--pause" ] && STATE=paused
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])")
SESSION="dm-$PROJ"
REG="${DM_REGISTRY:-$HOME/.delivery-machine/registry.json}"

# 1. handoff first — everything after this point is destructive
if bash "$HERE/handoff.sh"; then echo "handoff   .delivery/HANDOFF.md written"; else echo "handoff   FAILED (continuing)"; fi

# 2. Ctrl-C each service window that is actually up, so a server gets to shut down
if tmux has-session -t "$SESSION" 2>/dev/null; then
  WINS=$(tmux list-windows -t "$SESSION" -F '#W' 2>/dev/null)
  python3 -c "
import json;print('\n'.join(json.load(open('.delivery/config.json')).get('services', {})))" | while read -r w; do
    [ -n "$w" ] || continue
    if printf '%s\n' "$WINS" | grep -qx "$w"; then
      tmux send-keys -t "$SESSION:$w" C-c "" 2>/dev/null && echo "service   $w stopped (C-c)"
    else
      echo "service   $w not running"
    fi
  done
else
  echo "service   machine not running — nothing to stop"
fi

# 3. the session itself, unless we were asked to leave it up
if [ "$STATE" = paused ]; then
  echo "session   $SESSION left running (--pause)"
elif tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION" 2>/dev/null && echo "session   $SESSION killed" || echo "session   $SESSION would not die"
else
  echo "session   $SESSION was not running"
fi

# 4. the registry: state + when, entry kept
DM_STATE="$STATE" python3 - "$REG" "$PROJ" <<'PY'
import json, os, sys, time
reg_path, proj = sys.argv[1], sys.argv[2]
try:
    reg = json.load(open(reg_path))
except Exception:
    print(f"registry  {reg_path} unreadable — state not recorded"); raise SystemExit(0)
if proj not in reg:
    print(f"registry  no entry for {proj} — nothing to mark"); raise SystemExit(0)
reg[proj]["state"] = os.environ["DM_STATE"]
reg[proj]["stopped"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
json.dump(reg, open(reg_path, "w"), indent=2)
print(f"registry  {proj} marked {reg[proj]['state']} at {reg[proj]['stopped']}")
PY
