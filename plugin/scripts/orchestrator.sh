#!/usr/bin/env bash
# janus orchestrator — idempotent. Spins the tmux session, service
# windows, mission control, and registers the machine in the fleet registry.
# Usage: orchestrator.sh [--no-open]   (run from the project root)
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ_DIR="$(pwd)"
CONF="$PROJ_DIR/.delivery/config.json"
[ -f "$CONF" ] || { echo "no .delivery/config.json — run /dm-init in Claude first"; exit 1; }

PROJ=$(python3 -c "import json;print(json.load(open('$CONF'))['project'])")
SESSION="dm-$PROJ"
REG_DIR="$HOME/.delivery-machine"; mkdir -p "$REG_DIR"
REG="$REG_DIR/registry.json"; [ -f "$REG" ] || echo '{}' > "$REG"

# ---- ports: reuse registered, else first free. 5501+ dashboard, 5601+ ttyd
read -r PORT TTYD_PORT < <(python3 - "$REG" "$PROJ" <<'EOF'
import json, sys
reg_path, proj = sys.argv[1], sys.argv[2]
reg = json.load(open(reg_path))
def pick(key, lo, hi):
    p = reg.get(proj, {}).get(key)
    if p: return p
    taken = {v.get(key) for v in reg.values()}
    return next(p for p in range(lo, hi) if p not in taken)
print(pick("port", 5501, 5600), pick("ttyd_port", 5601, 5700))
EOF
)

# ---- tmux session + service windows (window per service; idempotent)
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux new-session -d -s "$SESSION" -n control -c "$PROJ_DIR"
  tmux send-keys -t "$SESSION:control" "echo janus control pane — $PROJ" Enter
fi
PRE=""   # keychain secrets only when config asks; other projects see the command unchanged
if [ "$(python3 -c "import json;print(bool(json.load(open('$CONF')).get('secrets')))")" = True ]; then
  PRE="eval \"\$(bash '$PLUGIN_ROOT/scripts/secrets-env.sh')\"; "
fi
python3 -c "
import json
for name, cmd in json.load(open('$CONF')).get('services', {}).items():
    print(f'{name}\t{cmd}')" | while IFS=$'\t' read -r name cmd; do
  if ! tmux list-windows -t "$SESSION" -F '#W' | grep -qx "$name"; then
    tmux new-window -t "$SESSION" -n "$name" -c "$PROJ_DIR"
    tmux send-keys -t "$SESSION:$name" "$PRE$cmd" Enter
  fi
done

# ---- the cockpit (mission-control plugin) is optional: beside this repo, or in a plugin cache, or absent
MC=""
for c in "${DM_MISSION_CONTROL:-}" "$PLUGIN_ROOT/../plugin-mc/mission-control" \
         $(ls -d "$HOME"/.claude*/plugins/cache/*/mission-control/*/mission-control 2>/dev/null | sort -V | tail -1); do
  [ -n "$c" ] && [ -f "$c/server.js" ] && { MC="$(cd "$c" && pwd)"; break; }
done

# ---- mission control window
if [ -n "$MC" ] && ! tmux list-windows -t "$SESSION" -F '#W' | grep -qx "mission"; then
  tmux new-window -t "$SESSION" -n mission -c "$PROJ_DIR"
  tmux send-keys -t "$SESSION:mission" \
    "node '$MC/server.js' --port $PORT --project '$PROJ_DIR' --session '$SESSION' --scripts '$PLUGIN_ROOT/scripts'" Enter
fi
[ -n "$MC" ] || echo "  cockpit   not installed — files + tmux only.  claude plugin install mission-control@janus-marketplace"

# ---- web terminal (ttyd) — every tile is a real terminal when this runs
if [ -n "$MC" ] && command -v ttyd >/dev/null 2>&1; then
  if ! tmux list-windows -t "$SESSION" -F '#W' | grep -qx "ttyd"; then
    XT=$(python3 -c "import json;t=json.load(open('$MC/theme.json'));print(json.dumps(t['xterm']),t['font']['size'])")
    XTHEME=${XT% *}; XSIZE=${XT##* }
    tmux new-window -t "$SESSION" -n ttyd -c "$PROJ_DIR"
    # 127.0.0.1 on purpose and not configurable: this is a shell in a browser
    tmux send-keys -t "$SESSION:ttyd" \
      "bash '$PLUGIN_ROOT/scripts/ttyd-run.sh' -i 127.0.0.1 -p $TTYD_PORT -W -a -t 'fontFamily=IBM Plex Mono, Menlo, monospace' -t fontSize=$XSIZE -t 'theme=$XTHEME' -t disableLeaveAlert=true bash '$PLUGIN_ROOT/scripts/dm-attach.sh'" Enter
  fi
else
  TTYD_PORT=""
  echo "  ttyd not installed — terminal tiles will be read-only snapshots. brew install ttyd, then rerun."
fi

# ---- pickup watcher window (answers inbox items when no session is live)
if ! tmux list-windows -t "$SESSION" -F '#W' | grep -qx "watch"; then
  tmux new-window -t "$SESSION" -n watch -c "$PROJ_DIR"
  tmux send-keys -t "$SESSION:watch" "bash '$PLUGIN_ROOT/scripts/watch.sh'" Enter
fi

# ---- register in the fleet
python3 - "$REG" "$PROJ" "$PROJ_DIR" "$SESSION" "$PORT" "${TTYD_PORT:-}" <<'EOF'
import json, sys, time
reg_path, proj, pdir, session, port, tport = sys.argv[1:7]
reg = json.load(open(reg_path))
reg[proj] = {"dir": pdir, "session": session, "port": int(port), "ttyd_port": int(tport) if tport else None,
             "started": time.strftime("%Y-%m-%d %H:%M")}
json.dump(reg, open(reg_path, "w"), indent=2)
EOF

echo "── janus up ───────────────────────────────────"
echo "  project   $PROJ"
echo "  session   $SESSION   (tmux attach -t $SESSION)"
[ -n "$MC" ] && echo "  mission   http://localhost:$PORT"
if [ -n "${TTYD_PORT:-}" ]; then echo "  terminal  http://127.0.0.1:$TTYD_PORT/?arg=control"; else echo "  terminal  (ttyd missing)"; fi
tmux list-windows -t "$SESSION" -F '  window    #W'
bash "$PLUGIN_ROOT/scripts/dm-prune.sh" | sed 's/^/  /' || true
[ "${1:-}" = "--no-open" ] || open "http://localhost:$PORT" 2>/dev/null || true
