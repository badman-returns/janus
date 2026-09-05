#!/usr/bin/env bash
# Resolve a registered machine's directory. The name is operator input — it arrives from Telegram,
# from a note, from dictation — so it is checked as a *name* in the shell and then handed to Python
# as an argument. It is never pasted into Python source: a name like
# `a']); import os; os.system('...') #` used to close the subscript and run whatever followed.
# Prints the directory on stdout; on refusal prints `<who>: <reason>` on stderr and exits 1.
# Usage: DIR=$(machine-dir.sh <machine> <who>) || exit 1
set -uo pipefail
NAME=${1-}; WHO=${2:-machine-dir}
case "$NAME" in ""|*[!A-Za-z0-9._-]*) echo "$WHO: bad machine name" >&2; exit 1 ;; esac
python3 - "$NAME" <<'EOF' 2>/dev/null || { echo "$WHO: no machine $NAME" >&2; exit 1; }
import json, os, sys
print(json.load(open(os.path.expanduser("~/.delivery-machine/registry.json")))[sys.argv[1]]["dir"])
EOF
