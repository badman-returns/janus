#!/usr/bin/env python3
"""Turn a reply (markdown) into the sentences Janus speaks, and read the optional header lines a
reply may start with. Headings, code, tables and link targets are dropped; emphasis marks go;
numbers stay. --selftest is the contract. stdlib only."""
import re, sys

def split_header(text):
    """Header lines `via: …`, `speak: …`, `needs: …`, `from: …`, `refs: …` before the first blank
    line. Returns (headers, body). A reply with no header block comes back unchanged. `refs:` (the
    files an answer was taken from) is never spoken — callers read it, sentences() never sees it."""
    lines = text.split('\n'); hdr = {}; i = 0
    while i < len(lines) and re.match(r'^(via|speak|needs|from|refs): ', lines[i]):
        k, v = lines[i].split(': ', 1); hdr[k] = v.strip(); i += 1
    if not hdr: return {}, text
    if i < len(lines) and lines[i].strip() == '': i += 1
    return hdr, '\n'.join(lines[i:])

def sentences(md):
    t = re.sub(r'```.*?```', ' ', md, flags=re.S)                       # code blocks
    t = re.sub(r'`([^`]*)`', r'\1', t)                                   # inline code keeps its text
    t = re.sub(r'^\s{0,3}#{1,6}\s+.*$', ' ', t, flags=re.M)              # headings
    t = re.sub(r'^\s*\|.*\|\s*$', ' ', t, flags=re.M)                    # table rows
    t = re.sub(r'!\[[^\]]*\]\([^)]*\)', ' ', t)                           # images
    t = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', t)                       # links keep their text
    t = re.sub(r'^\s*[-*+]\s+|^\s*\d+[.)]\s+', '', t, flags=re.M)         # list markers
    t = re.sub(r'[*_]{1,3}([^*_]+)[*_]{1,3}', r'\1', t)                   # emphasis
    t = re.sub(r'\s+', ' ', t).strip()
    parts = re.split(r'(?<=[.!?])\s+(?=[A-Z0-9"“(])', t)                 # ponytail: "Dr. Who" splits; fine for replies
    return [p.strip() for p in parts if re.search(r'\w', p)]

def selftest():
    md = ("via: shop-web\nspeak: yes\n\n## Brief\nTwo things. The field team finished **back-dating**; see "
          "[the video](proof/x.mp4). Count went to 2!\n```\nignored()\n```\n- Want the video?")
    h, b = split_header(md); assert h == {'via': 'shop-web', 'speak': 'yes'}, h
    s = sentences(b)
    assert s == ['Two things.', 'The field team finished back-dating; see the video.', 'Count went to 2!', 'Want the video?'], s
    assert split_header('plain text') == ({}, 'plain text')
    assert sentences('') == []
    h2, b2 = split_header('refs: wiki/shop/status.md raw/meetings/x.md\n\nDone.')
    assert h2 == {'refs': 'wiki/shop/status.md raw/meetings/x.md'}, h2
    assert b2 == 'Done.', b2
    print('PASS speech selftest')

if __name__ == '__main__':
    if '--selftest' in sys.argv: selftest()
    else: print('\n'.join(sentences(split_header(sys.stdin.read())[1])))
