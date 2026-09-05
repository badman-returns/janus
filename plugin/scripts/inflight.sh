#!/usr/bin/env bash
# JSON of every slice whose last ledger line is not `done`, with its checklist. Read by the feeder.
set -uo pipefail
python3 - <<'EOF'
import json, os, glob
reg = json.load(open(os.path.expanduser("~/.delivery-machine/registry.json")))
out = []
for proj, m in reg.items():
    d = m.get("dir", "")
    try: lines = [json.loads(l) for l in open(f"{d}/.delivery/runs.jsonl").read().splitlines() if l.strip()]
    except Exception: continue
    last_by_slice = {}
    for e in lines: last_by_slice[e["slice"]] = e
    for s, e in last_by_slice.items():
        if e["status"] == "done": continue
        ck = None
        p = f"{d}/.delivery/checklist/{s}.json"
        if os.path.exists(p):
            c = json.load(open(p)); ck = {"intent": c.get("intent"), "items": [{"text": i["text"], "proof": i["proof"], "done": i["done"]} for i in c.get("items", [])]}
        out.append({"project": proj, "slice": s, "status": e["status"], "agent": e["agent"], "ts": e["ts"], "checklist": ck})
print(json.dumps(out, indent=1))
EOF
