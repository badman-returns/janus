#!/usr/bin/env bash
# Every theme.json colour meets WCAG 2.1 against BOTH grounds it is drawn on (page bg and card
# surface): text 4.5:1, UI borders 3:1. The cockpit is read in daylight; --line at 1.29:1 made
# every card edge vanish under glare, which is the bug this guards against coming back.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$HERE/../../plugin-mc/mission-control/theme.json"
[ -f "$T" ] || { echo "FAIL test_theme_contrast: no theme.json"; exit 1; }

python3 - "$T" <<'PY' || exit 1
import json, sys, re

theme = json.load(open(sys.argv[1]))

def lum(h):
    h = h.lstrip('#')
    c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    l1, l2 = sorted([lum(a), lum(b)], reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)

# 3:1 is the WCAG 2.1 non-text threshold (1.4.11) — borders, dividers, focus rings.
NEEDS = {"ink": 4.5, "mut": 4.5, "mut2": 4.5, "line": 3.0, "line2": 3.0,
         "acc": 4.5, "ok": 4.5, "warn": 4.5, "bad": 4.5}
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")

fails = []
for mode in ("dark", "light"):
    t = theme[mode]
    grounds = [t["bg"], t["surface"]]          # the harder of the two is what counts
    for tok, need in NEEDS.items():
        v = t.get(tok)
        if not v or not HEX.match(v):
            fails.append(f"{mode}.{tok} missing or not a 6-digit hex: {v!r}")
            continue
        got = min(ratio(v, g) for g in grounds)
        if got < need:
            fails.append(f"{mode}.{tok} {v} is {got:.2f}:1, needs {need}:1")

if fails:
    print("FAIL test_theme_contrast:")
    for f in fails:
        print("  " + f)
    sys.exit(1)
PY

echo "PASS test_theme_contrast"
