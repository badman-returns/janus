#!/usr/bin/env bash
# Install (or --remove) a launchd agent that runs dm-boot.sh at login, so the
# machines come up without a terminal. Usage: install-login.sh [--remove]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.delivery-machine.boot"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/.delivery-machine/boot.log"

if [ "${1:-}" = "--remove" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"; echo "removed $PLIST"; exit 0
fi

mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$HERE/dm-boot.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "installed $PLIST (runs at login; log: $LOG)"
echo "remove:  launchctl unload $PLIST && rm $PLIST   (or: bash $HERE/install-login.sh --remove)"
