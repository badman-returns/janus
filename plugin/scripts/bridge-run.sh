#!/usr/bin/env bash
# Run ccgram bound to the `bridge` session. Secrets arrive in the environment from secrets-env.sh
# (TELEGRAM_BOT_TOKEN, ALLOWED_USERS). Non-secret settings live in ~/.ccgram/.env.
set -euo pipefail
# No apostrophe in these messages: inside "${VAR:?word}" bash reads a ' as an opening quote and
# swallows the rest — with "machine's" here the second guard silently disappeared.
: "${TELEGRAM_BOT_TOKEN:?set by the fleet machine secrets map}"
: "${ALLOWED_USERS:?set by the fleet machine secrets map}"
export TMUX_SESSION_NAME=bridge
bash "$(dirname "$0")/bridge-link.sh" >/dev/null 2>&1 || true
exec ccgram --tmux-session bridge
