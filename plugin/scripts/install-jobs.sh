#!/usr/bin/env bash
# Install (or --remove) the scheduled brain jobs as launchd agents: the 07:00 brief, the 02:00 miner,
# the Sunday 08:00 wiki lint. Every job sources job-guard.sh first, so `touch ~/.brain/PAUSED` stops
# all of them at once and `rm` starts them again — the kill switch is a file, not a launchctl dance.
# Usage: install-jobs.sh [--remove] [brief|miner|lint ...]     (no names = all three)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
U=$(id -u); DEST="$HOME/Library/LaunchAgents"
REMOVE=""; [ "${1:-}" = "--remove" ] && { REMOVE=1; shift; }
mkdir -p "$DEST" "$HOME/.brain"

for j in ${*:-brief miner lint}; do
  L="com.brain.$j"; SRC="$PLUGIN/templates/launchd/$L.plist"; P="$DEST/$L.plist"
  [ -f "$SRC" ] || { echo "no such job: $j"; continue; }
  launchctl bootout "gui/$U/$L" 2>/dev/null
  if [ -n "$REMOVE" ]; then rm -f "$P"; echo "removed  $L"; continue; fi
  sed -e "s|__PLUGIN__|$PLUGIN|g" -e "s|__HOME__|$HOME|g" "$SRC" > "$P"
  if launchctl bootstrap "gui/$U" "$P"; then
    echo "loaded   $L   $(plutil -extract StartCalendarInterval json -o - "$P")   log: $HOME/.brain/jobs.log"
  else
    echo "FAILED   $L   (launchctl bootstrap gui/$U $P)"
  fi
done
if [ -z "$REMOVE" ]; then
  echo "pause all: touch $HOME/.brain/PAUSED    resume: rm $HOME/.brain/PAUSED"
  case "$PLUGIN" in "$HOME/Documents"*|"$HOME/Desktop"*|"$HOME/Downloads"*)
    echo "note: launchd needs Full Disk Access for /bin/bash to run scripts under ~/Documents;"
    echo "      'Operation not permitted' in $HOME/.brain/jobs.log is that, not a bug in the job.";; esac
fi
