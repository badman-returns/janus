#!/usr/bin/env bash
# Runs every test_*.sh next to it; exit 1 if any fails.
cd "$(dirname "$0")"
rc=0
for t in test_*.sh; do bash "$t" || rc=1; done
exit $rc
