#!/usr/bin/env bash
# dm-gate.sh renders proof/<slice>/review.html from review.md and the branch diff — guide above the
# diff, a blank line in the guide becoming a paragraph break — and names it in the gate file. Then
# the PR path both ways: with no gh on PATH the gate opens with no `pr:` line at all, and with a gh
# and a remote it opens a draft PR whose body is the guide and records `pr: <url>`. GH_BIN is how
# the second half is reachable without a real remote — the first version of this test prepended a
# directory that did not exist and so proved nothing about gh either way.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; GATE="$HERE/../scripts/dm-gate.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail(){ echo "FAIL test_gate_review: $1"; exit 1; }
cd "$T" && git init -q -b main && mkdir -p .delivery/inbox proof/s bin && echo '{"project":"t","services":{}}' > .delivery/config.json
echo a > a.txt && git add -A && git commit -q -m one && git checkout -q -b s && echo b >> a.txt && git commit -q -am two
printf 'The change adds a line. Read a.txt first.\n\nIt is safe.\n' > proof/s/review.md; printf '# proof\n' > proof/s/README.md

# no gh: the page still renders and the gate file names it, but there is no PR
GH_BIN=/nonexistent/gh bash "$GATE" s >/dev/null 2>&1 || fail "dm-gate exited $?"
[ -s proof/s/review.html ] || fail "review.html not written"
grep -q 'Read a.txt first' proof/s/review.html || fail "guide missing from review.html"
grep -q '</p><p>' proof/s/review.html || fail "the guide's blank line did not become a paragraph break"
grep -q 'd2h\|diff2html' proof/s/review.html || fail "diff not rendered"
grep -q '^review: proof/s/review.html' .delivery/inbox/gate-s-proof.txt || fail "gate file does not name the review"
grep -q '^pr:' .delivery/inbox/gate-s-proof.txt && fail "a PR line without gh"

# gh and a remote: a draft PR with the guide as its body, and the url in the gate file
git init -q --bare "$T/remote.git" && git remote add origin "$T/remote.git"
cat > bin/gh <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >> gh.args
[ "$1" = pr ] && [ "$2" = create ] && echo https://example.test/pr/1
EOF
chmod +x bin/gh
GH_BIN="$T/bin/gh" bash "$GATE" s >/dev/null 2>&1 || fail "dm-gate with gh exited $?"
grep -q '^pr: https://example.test/pr/1' .delivery/inbox/gate-s-proof.txt || fail "gate file does not name the PR"
[ -s gh.args ] || fail "gh was never called"
grep -qx -- '--draft' gh.args || fail "gh was not called with --draft"
grep -qx -- '--body-file' gh.args || fail "gh was not called with --body-file"
grep -qx -- 'proof/s/review.md' gh.args || fail "the guide is not the PR body"
echo "PASS test_gate_review"
