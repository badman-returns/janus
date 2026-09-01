#!/usr/bin/env bash
# PreCompact hook — snapshot hard state into .delivery/HANDOFF.md before the
# conversation is summarized. Silent no-op outside a delivery-machine project.
set -uo pipefail
[ -d .delivery ] || exit 0
PROJ=$(python3 -c "import json;print(json.load(open('.delivery/config.json'))['project'])" 2>/dev/null || basename "$PWD")
{
  echo "# HANDOFF — $PROJ — $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "## Git"
  echo '```'
  git branch --show-current 2>/dev/null
  git status --short 2>/dev/null | head -30
  git log --oneline -5 2>/dev/null
  echo '```'
  echo
  echo "## Services (tmux dm-$PROJ)"
  echo '```'
  tmux list-windows -t "dm-$PROJ" -F '#W  #{pane_current_command}' 2>/dev/null || echo "machine not running"
  echo '```'
  echo
  echo "## Planning state"
  ls -t .planning 2>/dev/null | head -10 || echo "no .planning/"
  echo
  echo "## Inbox (pending operator/phone/voice items)"
  ls .delivery/inbox 2>/dev/null || echo "empty"
  echo
  echo "## Last runs"
  tail -5 .delivery/runs.jsonl 2>/dev/null || echo "none"
  echo
  echo "_Resume: read this, then continue the current step. Rules live in the /dm skill._"
} > .delivery/HANDOFF.md
exit 0
