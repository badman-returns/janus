#!/usr/bin/env python3
"""Download only the first N bytes of a remote .npy and leave a valid array behind.

openWakeWord's negatives are one 17.28 GB file; this Mac has ~15 GB free. A .npy is a header
followed by C-order rows, so a byte prefix is already a valid array the moment the leading
dimension in its header is rewritten to the number of whole rows that arrived. The header keeps
its exact byte length (numpy pads with spaces before the newline), so nothing after it shifts.

    python3 partial_npy.py <url> <out.npy> <byte-budget>      # budget 0 = the whole file

Resumable: bytes land in <out>.part and the file is renamed only once it loads.
"""
import ast, os, subprocess, sys, time

import numpy as np


def parse_header(head):
    """(offset of the first row, the header dict) from the first bytes of a .npy."""
    if head[:6] != b"\x93NUMPY":
        raise ValueError("not a .npy — first bytes are %r" % (head[:6],))
    n = 2 if head[6] == 1 else 4                       # v1 header length is uint16, v2+ uint32
    hlen = int.from_bytes(head[8:8 + n], "little")
    return 8 + n + hlen, ast.literal_eval(head[8 + n:8 + n + hlen].decode("latin1"))


def build_header(head, shape):
    """The same header bytes with a new shape — identical length, space-padded before the \\n."""
    n = 2 if head[6] == 1 else 4
    hlen = int.from_bytes(head[8:8 + n], "little")
    d = ast.literal_eval(head[8 + n:8 + n + hlen].decode("latin1"))
    s = "{'descr': '%s', 'fortran_order': %s, 'shape': (%s), }" % (
        d["descr"], d["fortran_order"], ", ".join(str(i) for i in shape))
    b = s.encode("latin1")
    if len(b) + 1 > hlen:
        raise ValueError("no room in the %d-byte header for shape %r" % (hlen, shape))
    return head[:8 + n] + b + b" " * (hlen - len(b) - 1) + b"\n"


def _curl(url, rng, append_to=None):
    """One ranged GET. To memory, or appended to a file. No --retry: a curl retry would replay the
    range from its start and duplicate bytes into the file we are appending to; the caller's loop
    recomputes the offset from the file's real size instead. The timeouts matter more than they
    look — without them a dead connection sat in DNS resolution for fifteen minutes at a time,
    where the loop would have re-asked for the rest of the range in thirty seconds."""
    cmd = ["curl", "-fsSL", "--connect-timeout", "20",
           "--speed-limit", "50000", "--speed-time", "30", "-r", rng, url]
    if append_to is None:
        return subprocess.run(cmd, check=True, capture_output=True).stdout
    with open(append_to, "ab") as f:
        return subprocess.run(cmd, stdout=f).returncode


def fetch(url, path, budget=0, attempts=40):
    """Leave `path` holding as many whole rows of the remote .npy as `budget` bytes allow."""
    if os.path.exists(path):
        return path
    part = path + ".part"
    head = _curl(url, "0-1023")
    off, hdr = parse_header(head)
    shape = tuple(hdr["shape"])
    row = int(np.prod(shape[1:])) * np.dtype(hdr["descr"]).itemsize
    total = off + shape[0] * row
    want = total if budget <= 0 or budget >= total else off + max(1, (budget - off) // row) * row
    rows = (want - off) // row
    print("  %s: %d of %d rows (%.2f of %.2f GB)"
          % (os.path.basename(path), rows, shape[0], want / 1e9, total / 1e9), flush=True)

    # 8 GB over a home connection is many minutes of HTTP/2, and the CDN drops the stream
    # ("CANCEL (err 8)") long before the end. Every pass re-asks for the range that is still
    # missing, so a drop costs nothing already on disk; only a pass that gains no bytes counts
    # against the budget, and any progress at all resets it.
    stalls = 0
    while stalls < attempts:
        have = os.path.getsize(part) if os.path.exists(part) else 0
        if have > want:                     # a bigger earlier budget, or a server that ignored the
            with open(part, "r+b") as f:    # range and sent the whole file — the prefix is still ours
                f.truncate(want)
            have = want
        if have >= want:
            break
        print("    resuming at %.2f of %.2f GB" % (have / 1e9, want / 1e9), flush=True)
        _curl(url, "%d-%d" % (have, want - 1), part)
        if os.path.getsize(part) > have:
            stalls = 0
        else:
            stalls += 1
            time.sleep(5)
    got = os.path.getsize(part) if os.path.exists(part) else 0
    if got != want:
        raise RuntimeError("%s: stalled at %d of %d bytes (%d passes gained nothing)"
                           % (path, got, want, attempts))

    if rows != shape[0]:
        with open(part, "r+b") as f:
            f.seek(0)
            f.write(build_header(head, (rows,) + shape[1:]))
    a = np.load(part, mmap_mode="r")        # the check: a bad header fails here, not two hours in
    assert a.shape == (rows,) + shape[1:], "shape %r, wanted %r" % (a.shape, (rows,) + shape[1:])
    assert a.dtype == np.dtype(hdr["descr"]), a.dtype
    assert np.isfinite(np.asarray(a[-1], dtype=np.float32)).all(), "last row is not finite"
    os.replace(part, path)
    return path


if __name__ == "__main__":
    fetch(sys.argv[1], sys.argv[2], int(float(sys.argv[3])) if len(sys.argv) > 3 else 0)
