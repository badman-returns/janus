#!/usr/bin/env bash
# Print `export VAR='value'` for every entry of config.json "secrets", read from
# the macOS keychain (generic password dm:<project>:<name>, value base64).
# Usage: eval "$(bash secrets-env.sh)"   (from the project root)
set -uo pipefail
python3 - <<'EOF2'
import base64, json, subprocess, sys
c = json.load(open(".delivery/config.json"))
for var, name in (c.get("secrets") or {}).items():
    item = f"dm:{c['project']}:{name}"
    r = subprocess.run(["security", "find-generic-password", "-s", item, "-w"], capture_output=True, text=True)
    if r.returncode:
        print(f"secrets-env: no keychain item {item} — {var} not set", file=sys.stderr); continue
    v = base64.b64decode(r.stdout).decode().rstrip("\n")   # like $(cat file): drop the trailing newline
    print(f"export {var}='" + v.replace("'", "'\\''") + "'")
EOF2
