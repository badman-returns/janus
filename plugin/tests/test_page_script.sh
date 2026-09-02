#!/usr/bin/env bash
# The dashboard's JS is inlined and the server injects into it by string replacement, so a
# mis-scoped placeholder produces a page that parses as HTML, serves 200, and is completely
# dead — every panel, every button, gone, with nothing in any log. This boots the real server
# and parses the script it actually serves.
#
# Written after `.replace("/*__X__*/", json)` against source that read `/*__X__*/null` emitted
# `{...}null;`. curl-and-grep saw the JSON and passed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SRV="$HERE/../../plugin-mc/mission-control/server.js"
T=$(mktemp -d); PORT=5597; PID=""
trap '[ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_page_script: $1"; exit 1; }

mkdir -p "$T/proj/.delivery/inbox"
echo '{"project":"t"}' > "$T/proj/.delivery/config.json"

node "$SRV" --port $PORT --project "$T/proj" --session dm-none >/dev/null 2>&1 & PID=$!; disown
for i in $(seq 1 40); do curl -sf "localhost:$PORT/api/state" >/dev/null && break; sleep 0.25; done
curl -sf "localhost:$PORT/api/state" >/dev/null || fail "server did not come up on $PORT"

for page in "/" "/fleet"; do
  curl -sf "localhost:$PORT$page" > "$T/page.html" || fail "$page did not serve"

  # every inline <script> the browser would run, concatenated as the browser sees them
  python3 - "$T/page.html" "$T/page.js" <<'EOF' || fail "$page: could not extract script"
import re, sys
html = open(sys.argv[1], encoding="utf8").read()
blocks = re.findall(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", html, re.S | re.I)
open(sys.argv[2], "w", encoding="utf8").write("\n;\n".join(blocks))
EOF

  [ -s "$T/page.js" ] || fail "$page served no inline script"
  node --check "$T/page.js" 2>"$T/err" || fail "$page inline script does not parse: $(head -3 "$T/err")"

  # no placeholder may survive into the served page — an unreplaced one is a silent hole
  grep -oE '/\*__[A-Z_]+__\*/' "$T/page.html" && fail "$page still contains an unreplaced placeholder"
done

# and the CSS side: tokens must have been substituted, not left as the marker
curl -sf "localhost:$PORT/" | grep -q -- '--bg:#' || fail "theme tokens were not injected"

echo "PASS test_page_script"
