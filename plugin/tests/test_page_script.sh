#!/usr/bin/env bash
# The dashboard's CSS and JS are served as real files now, so a page can parse as HTML, serve
# 200, and still be completely dead — every panel, every button, gone, with nothing in any log
# — if one asset it references 404s, is served with the wrong content-type, or does not parse.
# This boots the real server, reads the page it actually serves, and follows every reference:
# each module (and each module those import, transitively) and each same-origin stylesheet
# must be 200 with the right type, and every piece of JS must parse as an ES module.
#
# Written after `.replace("/*__X__*/", json)` against source that read `/*__X__*/null` emitted
# `{...}null;`. curl-and-grep saw the JSON and passed. That injection is gone — the page now
# fetches /api/state — and the placeholder assertion below is what keeps it gone.
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

# walk both pages and everything they reference; each fetched JS file lands in $T/js/ for node
BASE="http://localhost:$PORT" OUT="$T/js" python3 - "/" "/fleet" > "$T/report" <<'EOF' || fail "asset walk"
import os, re, sys, urllib.request, urllib.error, pathlib, posixpath
base, out = os.environ["BASE"], pathlib.Path(os.environ["OUT"]); out.mkdir(exist_ok=True)
bad, n_js, n_css = [], 0, 0

def get(url):
    try:
        with urllib.request.urlopen(base + url) as r:
            return r.status, (r.headers.get("content-type") or "").lower(), r.read().decode("utf8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, "", ""
    except Exception as e:                  # a dead socket is a dead page, not a crashed test
        return f"no response ({type(e).__name__})", "", ""

for page in sys.argv[1:]:
    st, _, html = get(page)
    if st != 200: bad.append(f"{page} serves {st}"); continue
    if re.search(r"/\*__[A-Z_]+__\*/", html):
        bad.append(f"{page} still contains an unreplaced placeholder")

    mods = re.findall(r'<script[^>]*\btype=["\']module["\'][^>]*\bsrc=["\']([^"\']+)', html, re.I) \
         + re.findall(r'<script[^>]*\bsrc=["\']([^"\']+)["\'][^>]*\btype=["\']module["\']', html, re.I)
    css  = re.findall(r'<link[^>]*\brel=["\']stylesheet["\'][^>]*\bhref=["\']([^"\']+)', html, re.I)
    # an inline script would still run, so it is not allowed to hide from the parse check
    inline = [b for b in re.findall(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", html, re.S | re.I) if b.strip()]
    for i, body in enumerate(inline):
        (out / f"inline-{page.strip('/') or 'index'}-{i}.js").write_text(body, encoding="utf8")
        print("inline", page, i)
    if not mods and not inline:
        bad.append(f"{page} would run no JavaScript at all")
    if not css:
        bad.append(f"{page} references no stylesheet")

    for href in css:
        if href.startswith("http"): continue          # third-party fonts are not ours to serve
        st, ct, body = get(href)
        if st != 200: bad.append(f"{page} -> {href} serves {st}"); continue
        if not ct.startswith("text/css"): bad.append(f"{href} served as {ct!r}, not CSS")
        if not body.strip(): bad.append(f"{href} served empty")
        n_css += 1
        print("css", href, st, ct.split(";")[0])

    seen, queue = set(), list(mods)
    while queue:
        url = queue.pop(0)
        if url in seen or url.startswith("http"): continue
        seen.add(url)
        st, ct, body = get(url)
        if st != 200: bad.append(f"{page} -> {url} serves {st}"); continue
        if not ("javascript" in ct or "ecmascript" in ct):
            bad.append(f"{url} served as {ct!r}, not JavaScript")
        if not body.strip(): bad.append(f"{url} served empty")
        (out / url.strip("/").replace("/", "__")).write_text(body, encoding="utf8")
        n_js += 1
        print("js", url, st, ct.split(";")[0])
        # a broken leaf must not hide behind a working root
        for imp in re.findall(r'''(?:^|[\s;])(?:import|export)\b[^;\n]*?["'](\.[^"']+)["']''', body, re.M):
            queue.append(posixpath.normpath(posixpath.join(posixpath.dirname(url), imp)))

if n_js < 15: bad.append(f"only {n_js} JS modules reached — the module graph was not walked")
if bad:
    print("\n".join("  " + b for b in bad), file=sys.stderr)
    sys.exit(1)
print(f"total {n_js} js, {n_css} css")
EOF

# every served module and inline script must parse the way the browser will parse it
for f in "$T"/js/*.js; do
  node --input-type=module --check < "$f" 2>"$T/err" \
    || fail "$(basename "$f") does not parse: $(head -3 "$T/err")"
done

# every stylesheet carries the theme tokens, substituted, not left as a marker
for css in /style.css /fleet.css; do
  curl -sf "localhost:$PORT$css" > "$T/c" || fail "$css did not serve"
  grep -q -- '--bg:#' "$T/c" || fail "theme tokens were not injected into $css"
  grep -q ':root\[data-theme="light"\]{' "$T/c" || fail "$css has no light theme block"
done

# the static handler is scoped to the page's own assets: nothing else in the directory, no traversal
[ "$(curl -s -o /dev/null -w '%{http_code}' "localhost:$PORT/server.js")" = 404 ] || fail "server.js is served to the browser"
[ "$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "localhost:$PORT/js/../../../../etc/passwd")" = 404 ] || fail "path traversal was not refused"

echo "PASS test_page_script ($(tail -1 "$T/report"))"
