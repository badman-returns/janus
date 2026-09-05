#!/usr/bin/env bash
# Open Gate 2 for a slice: writes .delivery/inbox/gate-<slice>-proof.txt and
# pings the phone — but only when proof/<slice>/README.md is newer than the
# slice's newest commit (proof-fresh.sh). Stale or missing proof = exit 2 with
# the reason and no gate file: a gate that cannot fail is decoration.
# Usage: dm-gate.sh <slice>   (from the project root)
set -uo pipefail
[ -d .delivery ] || exit 1
SLICE=${1:?slice}
HERE=$(cd "$(dirname "$0")" && pwd)
BRANCH=$(bash "$HERE/proof-fresh.sh" "$SLICE") || exit 2
PROOF=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('proof_dir') or 'proof')" 2>/dev/null || echo proof)
mkdir -p .delivery/inbox
{
  echo "GATE 2 — review proof for $SLICE"
  echo
  echo "branch: $BRANCH"
  echo "$PROOF/$SLICE/:"
  ls -1 "$PROOF/$SLICE" | sed 's/^/  /'
  echo
  echo "APPROVE / REJECT with note"
} > ".delivery/inbox/gate-$SLICE-proof.txt"

# the narrated diff: the reviewer's guide above the branch's diff, one self-contained page
PLUG="$(cd "$HERE/.." && pwd)"; V="$PLUG/../plugin-mc/mission-control/vendor"
if [ -s "$PROOF/$SLICE/review.md" ] && [ -s "$V/diff2html.min.js" ]; then
  # the branch's base: main if it exists, else master, else the root commit
  for b in main master; do
    git rev-parse -q --verify "$b" >/dev/null && BASE=$(git merge-base HEAD "$b") && break
  done
  [ -n "${BASE:-}" ] || BASE=$(git rev-list --max-parents=0 HEAD | tail -1)
  python3 - "$PLUG/templates/review.html" "$PROOF/$SLICE" "$SLICE" "$V" "$BASE" <<'PY'
import sys, subprocess, html, pathlib
tpl, pdir, slice_, v, base = sys.argv[1:]
guide = html.escape(pathlib.Path(pdir, 'review.md').read_text()).replace('\n\n', '</p><p>').replace('\n', ' ')
diff = subprocess.run(['git', 'diff', base + '...HEAD'], capture_output=True, text=True).stdout or subprocess.run(['git', 'diff', base], capture_output=True, text=True).stdout
js = pathlib.Path(v, 'diff2html.min.js').read_text(); css = pathlib.Path(v, 'diff2html.min.css').read_text() if pathlib.Path(v, 'diff2html.min.css').exists() else ''
page = pathlib.Path(tpl).read_text().replace('__SLICE__', html.escape(slice_)).replace('__GUIDE__', guide).replace('__DIFF2HTML__', js).replace('__DIFF__', diff.replace('</script', '<\\/script'))
page = page.replace('</style>', css + '</style>', 1)
raw = page.index('<script type="text/plain" id="raw">'); render = page.index('<script>document.getElementById("diff")')
# the raw diff must precede the renderer
page = page[:render] + page[raw:page.index('</script>', raw) + 9] + page[render:raw] + page[page.index('</script>', raw) + 9:]
pathlib.Path(pdir, 'review.html').write_text(page)
PY
  echo "review: $PROOF/$SLICE/review.html" >> ".delivery/inbox/gate-$SLICE-proof.txt"
fi
# a draft PR where a remote and gh exist; the guide is the body
if command -v gh >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1 && [ -s "$PROOF/$SLICE/review.md" ]; then
  URL=$(gh pr create --draft --title "$SLICE" --body-file "$PROOF/$SLICE/review.md" 2>/dev/null || gh pr view --json url -q .url 2>/dev/null || true)
  [ -n "$URL" ] && echo "pr: $URL" >> ".delivery/inbox/gate-$SLICE-proof.txt"
fi

bash "$HERE/notify.sh" "GATE 2: $SLICE"
