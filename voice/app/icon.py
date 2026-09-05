#!/usr/bin/env python3
"""Draws Janus.app's icon: the same ring as the menu bar, at 1024 px, in the accent colour, on a
transparent ground. Reuses the PNG writer from voice/icons/make-icons.py — one hand-rolled
zlib/struct encoder in this repo is enough.

    python3 voice/app/icon.py out.png [size]

Antialiasing here is analytic rather than the menu bar's supersampling: the shape is a plain ring,
so coverage is a function of distance alone, and 1024x1024x16 samples of pure Python is a minute
of build time nobody needs.
"""
import importlib.util, os, sys

ACC = (0x93, 0xA3, 0xFF)          # theme.json dark.acc — the cockpit's accent
R, STROKE = 0.72, 0.20            # same proportions as the menu-bar ring

def _make_icons():
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'icons', 'make-icons.py')
    spec = importlib.util.spec_from_file_location('make_icons', os.path.normpath(p))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def ring_png(path, size=1024, colour=ACC):
    png = _make_icons().png
    half, band, r, g, b = size / 2, STROKE / 2 * size / 2, *colour
    rows = []
    for py in range(size):
        row = bytearray()
        dy = py + 0.5 - half
        for px in range(size):
            dx = px + 0.5 - half
            d = (dx * dx + dy * dy) ** 0.5
            a = band - abs(d - R * half) + 0.5      # 1 px of feather either side of the stroke
            row += bytes((r, g, b, max(0, min(255, round(255 * a)))))
        rows.append(bytes(row))
    png(path, size, rows)
    return path

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'Janus.png'
    print('icon:', ring_png(out, int(sys.argv[2]) if len(sys.argv) > 2 else 1024))
