#!/usr/bin/env bash
# JSON of what is actually in flight, for the feeder: every slice whose last ledger status is not
# `done` AND that still promises something (a checklist), plus the slice on the ledger's last line —
# the one PROTOCOL calls in flight — even before it has promised anything. Without the checklist
# test, any slice ever abandoned mid-status stayed "in flight" forever.
set -uo pipefail
python3 - <<'EOF'
import json, os, glob
reg = json.load(open(os.path.expanduser("~/.delivery-machine/registry.json")))
out = []
for proj, m in reg.items():
    d = m.get("dir", "")
    try: lines = [json.loads(l) for l in open(f"{d}/.delivery/runs.jsonl").read().splitlines() if l.strip()]
    except Exception: continue
    if not lines: continue
    last_by_slice = {}
    for e in lines: last_by_slice[e["slice"]] = e
    running = lines[-1]["slice"]
    for s, e in last_by_slice.items():
        if e["status"] == "done": continue
        ck = None
        p = f"{d}/.delivery/checklist/{s}.json"
        if os.path.exists(p):
            c = json.load(open(p)); ck = {"intent": c.get("intent"), "items": [{"text": i["text"], "proof": i["proof"], "done": i["done"]} for i in c.get("items", [])]}
        elif s != running: continue  # promised nothing and not the slice in flight — stale
        out.append({"project": proj, "slice": s, "status": e["status"], "agent": e["agent"], "ts": e["ts"], "checklist": ck})
print(json.dumps(out, indent=1))
EOF
