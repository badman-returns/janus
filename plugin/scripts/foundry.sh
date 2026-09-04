#!/usr/bin/env bash
# Skill foundry — detects repeated patterns in the machine's own record and,
# on the 3rd repeat, surfaces a skill candidate for the orchestrator to author.
# Detection only; authoring is the orchestrator's job (see the /dm skill).
# Run ad hoc, or from a cron/watch. Silent no-op outside a dm project.
set -uo pipefail
[ -d .delivery ] || exit 0
# It runs on every Stop, which some projects do not want. Only an explicit "foundry": false
# in config.json turns it off — a missing key, a missing config or unreadable JSON all keep the
# old behaviour, so no existing project changes because this switch appeared.
ON=$(python3 -c "import json;print(json.load(open('.delivery/config.json')).get('foundry',True))" 2>/dev/null || echo True)
[ "$ON" = False ] && exit 0
python3 - <<'EOF'
import json, os, collections, hashlib
def lines(p):
    try:
        return [json.loads(l) for l in open(p) if l.strip()]
    except Exception: return []

runs = lines(".delivery/runs.jsonl")
# config-miss log: one ask per line (freeform), if present
misses = []
if os.path.exists(".delivery/config-miss.log"):
    misses = [l.strip() for l in open(".delivery/config-miss.log") if l.strip()]

# two repeats count: an agent failing the same slice again, and the same note
# (first 40 chars) coming back across runs — slice-independent
counter = collections.Counter()
sample = {}
def seen(key, r, weight=1):
    if key: counter[key] += weight; sample.setdefault(key, r)
for r in runs:
    if r.get("status") == "failed":
        seen(f"{r.get('agent')} failed on {r.get('slice')}", r)
    seen((r.get("note") or "")[:40].strip(), r)
for m in misses:
    seen(m[:40].strip(), {"note": m}, 2)   # a config-miss weighs more

os.makedirs(".delivery/skill-candidates", exist_ok=True)
existing = set(os.listdir(".delivery/skill-candidates"))
new = 0
for key, n in counter.items():
    if n < 3: continue
    slug = hashlib.md5(key.encode()).hexdigest()[:8]
    fn = f"cand-{slug}.md"
    if fn in existing: continue
    with open(f".delivery/skill-candidates/{fn}", "w") as f:
        f.write(f"# Skill candidate (seen {n}x)\n\n")
        f.write(f"Recurring pattern: `{key}`\n\n")
        f.write(f"Sample: {json.dumps(sample.get(key,{}))}\n\n")
        f.write("The orchestrator should decide whether this deserves a skill in "
                ".claude/skills/, author it (writing-skills flow), and delete this file.\n")
    new += 1
    print(f"skill candidate: {key} (seen {n}x)")
if new == 0:
    print("no new skill candidates (need a pattern seen 3+ times)")
EOF
