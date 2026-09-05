#!/usr/bin/env bash
# The line a watcher types to make a machine answer its inbox. Which skill answers differs per
# machine — `pickup_skill` in .delivery/config.json, `dm` (build) by default, `concierge` on the
# fleet machine (route) — and a typed /word only reaches a session when it names a registered
# skill, so the name has to be right. Anything unreadable falls back to `dm`.
# Usage: pickup-line.sh   (from the project root)
set -uo pipefail
S=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('pickup_skill') or 'dm')" 2>/dev/null) || S=dm
echo "/${S:-dm} process the pending items in .delivery/inbox"
