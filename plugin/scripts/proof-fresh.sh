#!/usr/bin/env bash
# Is proof/<slice>/README.md newer than the slice's newest commit? The one
# freshness rule, shared by run-log.sh (done) and dm-gate.sh (Gate 2).
# Slice branch = any local branch named <slice> or ending in /<slice>; the
# newest of them counts; none → HEAD. Prints the branch on success.
# Usage: proof-fresh.sh <slice>   (from the project root; exit 2 + reason on stderr)
set -uo pipefail
SLICE=${1:?slice}
README="proof/$SLICE/README.md"
[ -f "$README" ] || { echo "proof/$SLICE/README.md missing" >&2; exit 2; }
NEWEST=$(git for-each-ref refs/heads --format='%(committerdate:unix) %(objectname:short) %(committerdate:iso-strict) %(refname:short)' \
  | awk -v s="$SLICE" '$4==s || substr($4, length($4)-length(s)) == "/" s' | sort -n | tail -1)
[ -n "$NEWEST" ] || NEWEST=$(git log -1 --format='%ct %h %cI HEAD')
set -- $NEWEST
MTIME=$(python3 -c 'import os,sys;print(int(os.path.getmtime(sys.argv[1])))' "$README")
[ "$MTIME" -ge "$1" ] || { echo "$README older than commit $2 at $3 ($4)" >&2; exit 2; }
echo "$4"
