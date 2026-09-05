#!/usr/bin/env bash
# Write an operator note into a machine's inbox, tagged as coming from Telegram. The machine's
# watcher types it into the live session; nothing else changes.
# Usage: fleet-route.sh <project> <text...>
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJ=${1:?project}; shift; TEXT="$*"; [ -n "$TEXT" ] || { echo "empty note" >&2; exit 1; }
DIR=$(bash "$HERE/machine-dir.sh" "$PROJ" fleet-route) || exit 1
SLUG=$(printf %s "$TEXT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-40)
MS=$(python3 -c "import time;print(int(time.time()*1000))")
mkdir -p "$DIR/.delivery/inbox"
printf 'from: telegram %s %s\n\n%s\n' "${FEED_CHAT_ID:-operator}" "$(date -u +%FT%TZ)" "$TEXT" > "$DIR/.delivery/inbox/note-$MS-tg-$SLUG.txt"
echo "note-$MS-tg-$SLUG.txt → $PROJ"
