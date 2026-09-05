#!/usr/bin/env bash
# One line per registered machine: liveness, last ledger line, waiting gates, checklist progress.
set -uo pipefail
REG="$HOME/.delivery-machine/registry.json"; [ -s "$REG" ] || { echo "no machines registered"; exit 0; }
python3 - "$REG" <<'EOF'
import json, os, sys, glob, time
reg = json.load(open(sys.argv[1]))
for proj, m in reg.items():
    d = m.get("dir", "")
    if not os.path.isdir(d): print(f"{proj} · missing · dir gone"); continue
    beats = glob.glob(f"{d}/.delivery/agents/*.json")
    live = "live" if any(time.time() - os.path.getmtime(b) < 120 for b in beats) else ("idle" if beats else "down")
    last = "no runs"
    try:
        e = json.loads(open(f"{d}/.delivery/runs.jsonl").read().strip().splitlines()[-1])
        last = f"{e['agent']} {e['status']} {e['slice']}"; slice_ = e["slice"]
    except Exception: slice_ = None
    gates = len(glob.glob(f"{d}/.delivery/inbox/gate-*.txt") + glob.glob(f"{d}/.delivery/inbox/ask-*.txt"))
    ck = "—"
    if slice_ and os.path.exists(f"{d}/.delivery/checklist/{slice_}.json"):
        items = json.load(open(f"{d}/.delivery/checklist/{slice_}.json")).get("items", [])
        ck = f"checklist {sum(1 for i in items if i.get('done'))}/{len(items)}"
    print(f"{proj} · {live} · {last} · gates:{gates} · {ck}")
EOF
