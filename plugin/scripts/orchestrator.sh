#!/usr/bin/env bash
# delivery-machine orchestrator — idempotent. Spins the tmux session, service
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

# ---- port: reuse registered, else first free in 5500-5599
PORT=$(python3 - "$REG" "$PROJ" <<'EOF'
import json, socket, sys
reg_path, proj = sys.argv[1], sys.argv[2]
reg = json.load(open(reg_path))
def free(p):
    s = socket.socket()
    try: s.bind(("127.0.0.1", p)); s.close(); return True
    except OSError: return False
port = reg.get(proj, {}).get("port")
if not port:
    taken = {v.get("port") for v in reg.values()}
    port = next(p for p in range(5501, 5600) if p not in taken)
print(port)
EOF
)

# ---- tmux session + service windows (window per service; idempotent)
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux new-session -d -s "$SESSION" -n control -c "$PROJ_DIR"
  tmux send-keys -t "$SESSION:control" "echo delivery-machine control pane — $PROJ" Enter
fi
python3 -c "
import json
for name, cmd in json.load(open('$CONF')).get('services', {}).items():
    print(f'{name}\t{cmd}')" | while IFS=$'\t' read -r name cmd; do
  if ! tmux list-windows -t "$SESSION" -F '#W' | grep -qx "$name"; then
    tmux new-window -t "$SESSION" -n "$name" -c "$PROJ_DIR"
    tmux send-keys -t "$SESSION:$name" "$cmd" Enter
  fi
done

# ---- mission control window
if ! tmux list-windows -t "$SESSION" -F '#W' | grep -qx "mission"; then
  tmux new-window -t "$SESSION" -n mission -c "$PROJ_DIR"
  tmux send-keys -t "$SESSION:mission" \
    "node '$PLUGIN_ROOT/mission-control/server.js' --port $PORT --project '$PROJ_DIR' --session '$SESSION'" Enter
fi

# ---- pickup watcher window (answers inbox items when no session is live)
if ! tmux list-windows -t "$SESSION" -F '#W' | grep -qx "watch"; then
  tmux new-window -t "$SESSION" -n watch -c "$PROJ_DIR"
  tmux send-keys -t "$SESSION:watch" "bash '$PLUGIN_ROOT/scripts/watch.sh'" Enter
fi

# ---- register in the fleet
python3 - "$REG" "$PROJ" "$PROJ_DIR" "$SESSION" "$PORT" <<'EOF'
import json, sys, time
reg_path, proj, pdir, session, port = sys.argv[1:6]
reg = json.load(open(reg_path))
reg[proj] = {"dir": pdir, "session": session, "port": int(port), "started": time.strftime("%Y-%m-%d %H:%M")}
json.dump(reg, open(reg_path, "w"), indent=2)
EOF

echo "── delivery machine up ──────────────────────────"
echo "  project   $PROJ"
echo "  session   $SESSION   (tmux attach -t $SESSION)"
echo "  mission   http://localhost:$PORT"
tmux list-windows -t "$SESSION" -F '  window    #W'
[ "${1:-}" = "--no-open" ] || open "http://localhost:$PORT" 2>/dev/null || true
