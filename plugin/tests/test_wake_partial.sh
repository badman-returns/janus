#!/usr/bin/env bash
# partial_npy.fetch downloads a byte prefix of a remote .npy and leaves a *valid* array behind:
# the header's leading dimension is rewritten to the whole rows that arrived, the header keeps its
# exact byte length, and the rows are byte-for-byte the original's. Budget here covers 37.5 rows of
# a (100, 16, 96) float16 file, so the answer must be exactly the first 37.
# Note: python3 -m http.server ignores Range and replies 200 with the whole body, so what runs here
# is the over-fetch-and-truncate branch. The 206/Content-Range path is the same arithmetic and was
# verified against the real Hugging Face endpoint.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; WAKE="$HERE/../../voice/wake"
PY="$HERE/../../voice/.venv/bin/python"; [ -x "$PY" ] || PY=python3
"$PY" -c "import numpy" 2>/dev/null || { echo "PASS test_wake_partial (skipped: no numpy)"; exit 0; }

T=$(mktemp -d); SRV=""; fail(){ echo "FAIL test_wake_partial: $1"; exit 1; }
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/srv"

"$PY" -c "
import numpy as np
a = np.random.default_rng(3).standard_normal((100, 16, 96)).astype(np.float16)
np.save('$T/srv/neg.npy', a)" || fail "could not build the fixture"

PORT=$("$PY" -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
"$PY" -m http.server "$PORT" --bind 127.0.0.1 --directory "$T/srv" >/dev/null 2>&1 &
SRV=$!; disown $SRV 2>/dev/null   # keep the pid, drop the job-table notice on kill
up=""
for _ in $(seq 40); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/neg.npy" && { up=1; break; }
  "$PY" -c "import time; time.sleep(0.25)"
done
[ -n "$up" ] || fail "http.server never came up on $PORT"

WAKE="$WAKE" T="$T" PORT="$PORT" "$PY" - <<'PY' || fail "assertions failed (above)"
import os, sys
sys.path.insert(0, os.environ["WAKE"])
import numpy as np, partial_npy

T = os.environ["T"]
src = np.load(f"{T}/srv/neg.npy")
off, hdr = partial_npy.parse_header(open(f"{T}/srv/neg.npy", "rb").read(1024))
row = 16 * 96 * 2
budget = off + int(37.5 * row)          # thirty-seven and a half rows: the half must not survive

out = partial_npy.fetch(f"http://127.0.0.1:{os.environ['PORT']}/neg.npy", f"{T}/got.npy", budget)
assert not os.path.exists(out + ".part"), "left a .part behind"
assert os.path.getsize(out) == off + 37 * row, os.path.getsize(out)

a = np.load(out, mmap_mode="r")
assert a.shape == (37, 16, 96), a.shape
assert a.dtype == np.float16, a.dtype
assert np.array_equal(np.asarray(a), src[:37]), "rows do not match the original"

o2, h2 = partial_npy.parse_header(open(out, "rb").read(1024))
assert (o2, h2["descr"], h2["fortran_order"]) == (off, hdr["descr"], False), (o2, h2)
print(f"ok: {budget - off} bytes of rows → {a.shape}, header still {off} bytes")

partial_npy.fetch(f"http://127.0.0.1:{os.environ['PORT']}/neg.npy", f"{T}/whole.npy", 0)
assert np.array_equal(np.load(f"{T}/whole.npy"), src), "budget 0 must give the whole file"
print("ok: budget 0 → all 100 rows")
PY
echo "PASS test_wake_partial"
