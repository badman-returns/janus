#!/usr/bin/env python3
"""Draws the menu-bar ring: one 22 px template PNG per state, plus a 44 px @2x, black on
transparent so macOS tints it (dark in a light menu bar, light in a dark one). Stdlib only —
zlib and struct write the PNG by hand; seven circles do not earn a Pillow dependency.

    voice/.venv/bin/python voice/icons/make-icons.py   # writes 14 files next to this script

Shapes, per the plan — seven states, seven different pictures, because the ring's shape is the only
thing that says which one: a ring for idle, a ring with a wide centre dot for listening, a ring with
a small one for thinking, a disc split by a bar for speaking, a heavy notched ring for waiting, a
faint ring for muted, a dashed ring for offline.
"""
import math, os, struct, sys, zlib

R, STROKE, DOT = 0.72, 0.20, 0.24   # ring radius, stroke width, centre dot — box is [-1, 1]
IN, OUT = R - STROKE / 2, R + STROKE / 2
TAU = math.tau

EYE = 0.44                          # listening's centre dot: wide open, twice thinking's
HEAVY = 0.34                        # waiting's ring, thicker than the rest so it reads as insistent
HIN, HOUT = R - HEAVY / 2, R + HEAVY / 2

def ring(d, a):    return IN <= d <= OUT
def disc(d, a):    return d <= OUT
def ring_dot(d, a): return ring(d, a) or d <= DOT
def ring_eye(d, a): return ring(d, a) or d <= EYE
def barred(d, a):  return disc(d, a) and abs(d * math.sin(a)) > 0.15   # a disc a mouth-line splits
def notched(d, a): return HIN <= d <= HOUT and not a < TAU / 8         # a heavy ring, one gap
def dashed(d, a):  return ring(d, a) and (a % (TAU / 6)) < (TAU / 6) * 0.6  # 6 chunky dashes: at
                   # 22 px a finer dash pattern turns to noise rather than reading as "not there"

STATES = {                    # state -> (shape, opacity)
    'idle':      (ring,     1.0),
    'listening': (ring_eye, 1.0),
    'thinking':  (ring_dot, 1.0),
    'speaking':  (barred,   1.0),
    'waiting':   (notched,  1.0),
    'muted':     (ring,     0.35),
    'offline':   (dashed,   1.0),
}

SS = 4  # supersampling per axis; 16 samples a pixel is enough antialiasing at 22 px

def rows(size, shape, opacity):
    """RGBA scanlines: black everywhere, the shape's coverage in alpha."""
    out = []
    for py in range(size):
        row = bytearray()
        for px in range(size):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    x = (px + (sx + 0.5) / SS) / size * 2 - 1
                    y = (py + (sy + 0.5) / SS) / size * 2 - 1
                    if shape(math.hypot(x, y), math.atan2(y, x) % TAU): hits += 1
            row += bytes((0, 0, 0, round(255 * opacity * hits / SS ** 2)))
        out.append(bytes(row))
    return out

def png(path, size, scanlines):
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data))
    ihdr = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)   # 8-bit RGBA, no interlace
    idat = zlib.compress(b''.join(b'\0' + s for s in scanlines), 9)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b''))

def alpha_sum(scanlines):
    return sum(s[3::4].count(255) for s in scanlines)

def main(out_dir=None):
    out_dir = out_dir or os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out_dir, exist_ok=True)
    ink = {}
    for state, (shape, opacity) in STATES.items():
        for size, suffix in ((22, ''), (44, '@2x')):
            s = rows(size, shape, opacity)
            png(os.path.join(out_dir, f'{state}{suffix}.png'), size, s)
            if size == 22: ink[state] = alpha_sum(s)
    # the check: the shapes must actually differ, or every state looks the same in the menu bar
    assert ink['listening'] > ink['thinking'] > ink['idle'] > 0, ink   # each centre dot adds ink
    assert ink['speaking'] > ink['waiting'] > ink['idle'], ink         # a split disc, then a heavy ring
    assert ink['offline'] < ink['idle'], ink                  # dashes remove half the ring
    assert ink['muted'] == 0, ink                             # faint: no fully opaque pixel
    assert len(set(ink.values())) == len(ink), ink            # seven states, seven pictures
    print(f'icons: {2 * len(STATES)} files in {out_dir}', ink)

if __name__ == '__main__': main(*sys.argv[1:])
