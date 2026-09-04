#!/usr/bin/env bash
# Bring every registered Janus machine up (idempotent). Run by launchd at login,
# or by hand. One line per project: started | already up | skipped-missing | skipped-stopped |
# skipped-paused | failed.
# Usage: dm-boot.sh
set -uo pipefail
# launchd gives no PATH worth having; node on this machine is a symlink in ~/.local/bin (not brew)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG="${DM_REGISTRY:-$HOME/.delivery-machine/registry.json}"
[ -f "$REG" ] || { echo "no registry at $REG"; exit 0; }

# A machine the operator stopped on purpose (dm-stop.sh writes state=stopped|paused) is not a
# crash to recover from — bringing it back at login would undo the decision. orchestrator.sh
# rewrites the entry when the machine is started again, which clears the state.
python3 -c "
import json
for name, v in json.load(open('$REG')).items(): print(f'{name}\t{v[\"dir\"]}\t{v.get(\"state\") or \"\"}')" | while IFS=$'\t' read -r name dir st; do
  case "$st" in stopped|paused) echo "skipped-$st $name"; continue ;; esac
  if [ ! -f "$dir/.delivery/config.json" ]; then echo "skipped-missing $name ($dir)"; continue; fi
  if tmux has-session -t "dm-$name" 2>/dev/null; then state="already up"; else state="started"; fi
  if (cd "$dir" && bash "$PLUGIN_ROOT/scripts/orchestrator.sh" --no-open >/dev/null 2>&1); then
    echo "$state $name"
  else
    echo "failed $name ($dir)"
  fi
done
