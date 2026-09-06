#!/usr/bin/env bash
# Install (or --remove) the scheduled brain jobs as launchd agents: the 07:00 brief, the 02:00 miner,
# the Sunday 08:00 wiki lint, the 03:00 foundry loop. Every job sources job-guard.sh first, so
# `touch ~/.brain/PAUSED` stops all of them at once and `rm` starts them again — the kill switch is
# a file, not a launchctl dance.
# Usage: install-jobs.sh [--remove] [brief|lint|miner|foundry ...]
# No names loads only the two that are safe to schedule blind: brief and lint. The miner needs
# Cognee's captured sessions (Task 7) and the foundry builds unattended, so each is named on purpose.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
U=$(id -u); DEST="$HOME/Library/LaunchAgents"
REMOVE=""; [ "${1:-}" = "--remove" ] && { REMOVE=1; shift; }
mkdir -p "$DEST" "$HOME/.brain"

for j in ${*:-brief lint}; do
  L="com.brain.$j"; SRC="$PLUGIN/templates/launchd/$L.plist"; P="$DEST/$L.plist"
  [ -f "$SRC" ] || { echo "no such job: $j"; continue; }
  launchctl bootout "gui/$U/$L" 2>/dev/null
  if [ -n "$REMOVE" ]; then rm -f "$P"; echo "removed  $L"; continue; fi
  sed -e "s|__PLUGIN__|$PLUGIN|g" -e "s|__HOME__|$HOME|g" "$SRC" > "$P"
  if launchctl bootstrap "gui/$U" "$P"; then
    echo "loaded   $L   $(plutil -extract StartCalendarInterval json -o - "$P")   log: $HOME/.brain/jobs.log"
    # a job launchd cannot execute exits 126 and is invisible until a brief stops arriving, so ask now.
    # INSTALL_JOBS_KICK=1 runs it immediately; without it the exit code is whatever the last run left.
    [ "${INSTALL_JOBS_KICK:-}" = 1 ] && launchctl kickstart -k "gui/$U/$L"
    LE=$(launchctl print "gui/$U/$L" 2>/dev/null | grep -m1 'last exit code' | sed 's/^[[:space:]]*//')
    echo "         ${LE:-last exit code = (not reported)}"
    # a job launchd has not run since this bootstrap reports "(never exited)": nothing to judge yet
    case "${LE:-}" in *"= 0"|*"never exited"*|*"not reported"*|"") ;; *)
      echo "         that is usually Full Disk Access: System Settings > Privacy & Security >"
      echo "         Full Disk Access > add /bin/bash, then re-run this script.";; esac
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
