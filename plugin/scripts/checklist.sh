#!/usr/bin/env bash
# The checklist a gated slice must declare before it may keep going: what will be done,
# and for each item the proof that will show it was. Lives at .delivery/checklist/<slice>.json
# so the runtime (gate-check.sh) and the cockpit can read it — see PROTOCOL.md.
#
# An item with no stated proof cannot be checked off later, so `add` refuses one: the
# proof is the whole point of writing the item down, not a field to fill in afterwards.
#
# Usage (from the project root):
#   checklist.sh init <slice> <intent> [trigger…]   # trigger = why this slice is gated
#   checklist.sh add <slice> <text> <proof>
#   checklist.sh check <slice> <index>              # 0-based, as printed by add/show
#   checklist.sh approve <slice>                    # operator's approval; stamps approved_at
#   checklist.sh show <slice>
# Refusal = exit 2, nothing written.
set -uo pipefail
[ -d .delivery ] || { echo "checklist: not a Janus project (no .delivery/)" >&2; exit 1; }
[ $# -ge 2 ] || { echo "checklist: usage: checklist.sh init|add|check|approve|show <slice> …" >&2; exit 2; }
python3 - "$@" <<'PY'
import json, os, sys, time

sub, slice_ = sys.argv[1], sys.argv[2]
def die(msg): print(f"checklist: {msg}", file=sys.stderr); sys.exit(2)
if "/" in slice_ or slice_ in (".", ".."): die(f"bad slice name {slice_!r}")
path = f".delivery/checklist/{slice_}.json"
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def load():
    try:
        return json.load(open(path))
    except FileNotFoundError:
        die(f"no checklist for {slice_!r} — run: checklist.sh init {slice_} '<intent>'")
    except Exception as e:
        die(f"{path} is unreadable: {e}")

def save(d):
    os.makedirs(".delivery/checklist", exist_ok=True)
    json.dump(d, open(path, "w"), indent=2)
    open(path, "a").write("\n")

def arg(n, what):
    if len(sys.argv) <= n or not sys.argv[n].strip(): die(f"{sub} needs <{what}>")
    return sys.argv[n]

if sub == "init":
    save({"slice": slice_, "intent": arg(3, "intent"), "gated": True,
          "triggers": [t for t in sys.argv[4:] if t.strip()],
          "approved_at": None, "items": []})
    print(f"checklist: {path} — declare items, then have the operator approve it")
elif sub == "add":
    text, proof = arg(3, "text"), arg(4, "proof")
    d = load()
    d["items"].append({"text": text, "proof": proof, "done": False, "ts": None})
    save(d)
    print(f"item {len(d['items']) - 1}: {text} — proof: {proof}")
elif sub == "check":
    i = arg(3, "index")
    d = load()
    try:
        item = d["items"][int(i)]
    except (ValueError, IndexError):
        die(f"no item {i} (0..{len(d['items']) - 1})")
    item["done"], item["ts"] = True, now
    save(d)
    print(f"item {i} done: {item['text']} — show the proof: {item['proof']}")
elif sub == "approve":
    d = load()
    d["approved_at"] = now
    save(d)
    print(f"checklist {slice_} approved at {now} — {len(d['items'])} item(s)")
elif sub == "show":
    d = load()
    print(f"{d['slice']} — {d['intent']}")
    print(f"  gated: {d.get('gated')} · approved: {d.get('approved_at') or 'NOT YET'}"
          + (f" · triggers: {', '.join(d.get('triggers') or [])}" if d.get("triggers") else ""))
    for n, it in enumerate(d.get("items") or []):
        print(f"  [{'x' if it.get('done') else ' '}] {n} {it.get('text')}"
              f"  — proof: {it.get('proof')}" + (f" ({it['ts']})" if it.get("ts") else ""))
    if not d.get("items"): print("  (no items yet)")
else:
    die(f"unknown subcommand {sub!r} (init|add|check|approve|show)")
PY
