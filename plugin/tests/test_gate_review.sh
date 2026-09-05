#!/usr/bin/env bash
# dm-gate.sh renders proof/<slice>/review.html from review.md and the branch diff, names it in the
# gate file, and skips the PR quietly when gh is absent.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; GATE="$HERE/../scripts/dm-gate.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_gate_review: $1"; exit 1; }
cd "$T" && git init -q -b main && mkdir -p .delivery/inbox proof/s && echo '{"project":"t","services":{}}' > .delivery/config.json
echo a > a.txt && git add -A && git commit -q -m one && git checkout -q -b s && echo b >> a.txt && git commit -q -am two
printf 'The change adds a line. Read a.txt first. It is safe.\n' > proof/s/review.md; printf '# proof\n' > proof/s/README.md
PATH="$T/nogh:$PATH" bash "$GATE" s >/dev/null 2>&1 || fail "dm-gate exited $?"
[ -s proof/s/review.html ] || fail "review.html not written"
grep -q 'Read a.txt first' proof/s/review.html || fail "guide missing from review.html"
grep -q 'd2h\|diff2html' proof/s/review.html || fail "diff not rendered"
grep -q '^review: proof/s/review.html' .delivery/inbox/gate-s-proof.txt || fail "gate file does not name the review"
grep -q '^pr:' .delivery/inbox/gate-s-proof.txt && fail "a PR line without gh"
echo "PASS test_gate_review"
