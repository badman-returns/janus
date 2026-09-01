#!/usr/bin/env bash
# Push a phone notification via ntfy (stage 2). No-op if no topic configured.
# Usage: notify.sh "message"
set -uo pipefail
TOPIC=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('ntfy_topic') or '')" 2>/dev/null)
[ -n "$TOPIC" ] || exit 0
curl -s -d "$1" "https://ntfy.sh/$TOPIC" > /dev/null || true
