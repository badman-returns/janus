#!/usr/bin/env bash
# The five bands, against a project that actually has something in every one of them.
#
# A panel in this cockpit is a pure function of the /api/state payload returning HTML — that
# is the whole convention (js/panels/index.js) — so a test can boot the real server, take the
# real payload, and call the real panels in node. "200 OK" proves nothing about a band: what
# has to hold is that the fixture's own content comes out the other end. Three things get
# checked per band: that /api/state carries the data at all, that the panel renders THIS
# project's values, and — for the two bands that are mostly empty in real life — that the
# empty case says something the operator can act on.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MC="$HERE/../../plugin-mc/mission-control"; SRV="$MC/server.js"
T=$(mktemp -d); PORT=5596; PID=""
trap '[ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FAIL test_cockpit_bands: $1"; exit 1; }
P="$T/proj"

# ---------- a project with a gate, an ask, two agents in flight, checklists, knowledge and proof
mkdir -p "$P/.delivery/inbox" "$P/.delivery/checklist" "$P/.delivery/agents" \
         "$P/docs/decisions" "$P/proof/login" "$T/outside/memory"
cd "$P"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q
echo '{"project":"bandtest"}' > .delivery/config.json

# band 1 — one gate, one ask, and one file the operator wrote (which must not count as waiting)
printf 'Plan for login is in .planning/specs. APPROVE or REJECT: <note>\n' > .delivery/inbox/gate-plan-login.txt
printf '{"kind":"ask","title":"which pdf lib","questions":[{"question":"Pick one","options":["pdfkit","puppeteer"],"multi":false}]}\n' \
  > .delivery/inbox/ask-1700000000-which-pdf-lib.txt
printf 'RE: gate-old.txt\nAPPROVE\n' > .delivery/inbox/reply-1699999999-gate-old-txt.txt

# band 2 — newest row per slice decides: login and signup are dispatched (in flight), legacy is not
printf '%s\n' \
 '{"ts":"2026-09-04T09:00:00Z","agent":"dm-builder","slice":"login","status":"dispatched","note":"round 1"}' \
 '{"ts":"2026-09-04T09:20:00Z","agent":"dm-reviewer","slice":"login","status":"reviewed","note":"two findings"}' \
 '{"ts":"2026-09-04T09:30:00Z","agent":"dm-builder","slice":"legacy","status":"built","note":"finished long ago"}' \
 '{"ts":"2026-09-04T09:40:00Z","agent":"dm-architect","slice":"signup","status":"dispatched","note":"planning"}' \
 '{"ts":"2026-09-04T09:50:00Z","agent":"dm-builder","slice":"login","status":"dispatched","note":"round 2"}' \
 > .delivery/runs.jsonl

# heartbeats: one live in login's own worktree (a real join), one 5 min stale (must not be "live")
NOW=$(python3 -c "import time;print(time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()))")
OLD=$(python3 -c "import time;print(time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(time.time()-300)))")
printf '{"sid":"ab12cd34","ts":"%s","event":"tool","detail":"Bash: yarn test --run","role":"session","cwd":"login"}\n' \
  "$NOW" > .delivery/agents/ab12cd34.json
printf '{"sid":"deadbeef","ts":"%s","event":"stop","detail":"turn finished","role":"session","cwd":"proj"}\n' \
  "$OLD" > .delivery/agents/deadbeef.json

# the checklist panel: login is approved and half done, signup is gated and NOT approved
cat > .delivery/checklist/login.json <<'JSON'
{ "slice": "login", "intent": "let a user sign in with a magic link", "gated": true,
  "triggers": ["files>4", "guarded:src/shared/auth/can.ts"],
  "approved_at": "2026-09-04T08:55:00Z",
  "items": [ {"text":"token table + migration","proof":"migration output pasted in the PR","done":true,"ts":"2026-09-04T09:10:00Z"},
             {"text":"send the mail","proof":"screenshot of the inbox","done":false,"ts":null},
             {"text":"expiry test","proof":"vitest run, one failing case first","done":false,"ts":null} ] }
JSON
cat > .delivery/checklist/signup.json <<'JSON'
{ "slice": "signup", "intent": "collect a company name at signup", "gated": true,
  "triggers": ["files>4"], "approved_at": null,
  "items": [ {"text":"form field","proof":"screenshot","done":false,"ts":null} ] }
JSON

# band 5 — two repo-local writes to one path, and one absolute path OUTSIDE the project
echo 'D-1: use magic links' > docs/decisions/0001-magic-links.md
git add -A && git commit -qm one
echo 'D-2: 15 minute expiry' >> docs/decisions/0001-magic-links.md      # uncommitted -> a diffstat
: > "$T/outside/memory/MEMORY.md"
printf '%s\t%s\t%s\n' \
  "2026-09-04T09:01:00Z" "docs/decisions/0001-magic-links.md" "write" \
  "2026-09-04T09:02:00Z" "docs/decisions/0001-magic-links.md" "edit" \
  "2026-09-04T09:03:00Z" "$T/outside/memory/MEMORY.md" "write" > .delivery/knowledge.log

# band 4 — proof, and a handoff for the top bar
echo 'proves the login slice' > proof/login/README.md
printf 'PNG-ish\n' > proof/login/shot.png
echo '# handoff: mid-way through login round 2' > .delivery/HANDOFF.md

# ---------- the real server, the real payload
node "$SRV" --port $PORT --project "$P" --session dm-none >/dev/null 2>&1 & PID=$!; disown
for i in $(seq 1 40); do curl -sf "localhost:$PORT/api/state" >/dev/null && break; sleep 0.25; done
curl -sf "localhost:$PORT/api/state" > "$T/state.json" || fail "server did not come up on $PORT"

python3 - "$T/state.json" "$T/outside/memory/MEMORY.md" <<'EOF' || fail "/api/state additions"
import json, sys
s = json.load(open(sys.argv[1])); outside = sys.argv[2]

# checklist: every slice's, because band 2 joins them by name
cl = {c["slice"]: c for c in s["checklist"]}
assert set(cl) == {"login", "signup"}, list(cl)
assert cl["login"]["approved_at"] == "2026-09-04T08:55:00Z", cl["login"]
assert cl["signup"]["approved_at"] is None and cl["signup"]["gated"] is True, cl["signup"]
assert [i["done"] for i in cl["login"]["items"]] == [True, False, False], cl["login"]["items"]
assert cl["login"]["items"][1]["proof"] == "screenshot of the inbox", cl["login"]["items"][1]

# knowledge: grouped by path, newest first, counted, and the outside path flagged
k = s["knowledge"]
assert k["writes"] == 3, k
assert [p["path"] for p in k["paths"]] == [outside, "docs/decisions/0001-magic-links.md"], k["paths"]
assert k["paths"][0]["outside"] is True, k["paths"][0]
assert k["paths"][1]["outside"] is False, k["paths"][1]
assert k["paths"][1]["count"] == 2 and set(k["paths"][1]["kinds"]) == {"write", "edit"}, k["paths"][1]
assert "0001-magic-links.md" in k["diffstat"], repr(k["diffstat"])
assert outside not in k["diffstat"], "git was asked about a path outside the repo"

# handoff age, not just its body
assert s["handoff_mtime"] and s["handoff_mtime"].startswith("20"), s.get("handoff_mtime")
assert s["handoff"].startswith("# handoff"), s["handoff"]

# heartbeat liveness is the server's call (120s, per is-live.sh) — the band trusts it
live = {a["sid"]: a["alive"] for a in s["agents"]}
assert live == {"ab12cd34": True, "deadbeef": False}, live
EOF

# the slice-story drawer reads the same checklist through /api/slice
curl -sf "localhost:$PORT/api/slice?name=login" > "$T/slice.json" || fail "/api/slice failed"
python3 -c "
import json,sys; d=json.load(open('$T/slice.json'))
assert d['checklist'] and d['checklist']['slice']=='login', d.get('checklist')
assert len(d['checklist']['items'])==3, d['checklist']" || fail "/api/slice carries no checklist"

# ---------- render every band from that payload, the way the browser will
python3 - "$T/state.json" "$T/state-quiet.json" <<'EOF' || fail "could not derive the quiet payload"
import json, sys
s = json.load(open(sys.argv[1]))
s["inbox"] = [i for i in s["inbox"] if i["name"].startswith(("reply-", "note-"))]   # nothing waiting
json.dump(s, open(sys.argv[2], "w"))
EOF

# one file per band, so an assertion about band 2 cannot be satisfied by band 4's HTML
cat > "$T/render.mjs" <<MJS
import fs from "fs";
import gates from "$MC/js/panels/gates.js";
import inflight from "$MC/js/panels/inflight.js";
import runs from "$MC/js/panels/runs.js";
import proof from "$MC/js/panels/proof.js";
import knowledge from "$MC/js/panels/knowledge.js";
import checklist from "$MC/js/panels/checklist.js";
const s = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
for (const [k, p] of Object.entries({ gates, inflight, runs, proof, knowledge, checklist })) {
  const d = p(s);
  fs.writeFileSync(\`\${process.argv[3]}/\${k}.html\`,
    \`--- \${k} name=\${d.name} size=\${d.size || "-"} count=\${d.count} alert=\${!!d.alert}\n\` + d.body());
}
MJS
mkdir -p "$T/b" "$T/q"
node "$T/render.mjs" "$T/state.json"       "$T/b" 2>"$T/err" || fail "panels threw: $(head -5 "$T/err")"
node "$T/render.mjs" "$T/state-quiet.json" "$T/q" 2>"$T/err" || fail "panels threw (quiet): $(head -5 "$T/err")"

has(){ grep -qF -- "$2" "$T/$1" || fail "$3"; }
hasnt(){ ! grep -qF -- "$2" "$T/$1" || fail "$3"; }

# band 1 — the gate and the ask, with their real bodies and their buttons
has b/gates.html 'gate-plan-login.txt'                    "band 1 does not name the gate"
has b/gates.html 'APPROVE or REJECT'                      "band 1 does not show the gate body"
has b/gates.html 'data-act="approve" data-re="gate-plan-login.txt"' "band 1 lost the approve button"
has b/gates.html 'data-act="reject"'                      "band 1 lost the reject button"
has b/gates.html 'question · which pdf lib'               "band 1 does not render the ask card"
has b/gates.html 'value="puppeteer"'                      "band 1 does not render the ask's options"
has b/gates.html '--- gates name=Waiting on you size=l count=2' "band 1 does not count exactly the gate and the ask"
hasnt b/gates.html 'data-re="reply-1699999999-gate-old-txt.txt"' "band 1 offers to approve the operator's own reply"
has b/gates.html 'awaiting pickup'                        "band 1 lost the operator's own writing awaiting pickup"
# and the zero-state is the signal, so it has to carry what IS happening
has q/gates.html 'Nothing is waiting on you'              "band 1's empty state does not say so"
has q/gates.html '2 agents in flight'                     "band 1's empty state does not say what is running"
has q/gates.html 'builder on login'                       "band 1's empty state does not name the agents"
has q/gates.html 'ntfy_topic'                             "band 1's empty state does not say what would land here"

# band 2 — one row per running agent: role · slice · round · elapsed · current item · last tool
has b/inflight.html '--- inflight name=Now — in flight size=l count=2' "band 2 is not a full-width band with 2 rows"
has b/inflight.html '>builder<'                           "band 2 does not show the role"
has b/inflight.html '>architect<'                         "band 2 missed the second dispatched slice"
has b/inflight.html 'data-slice="login"'                  "band 2 does not link the slice to its story"
has b/inflight.html 'round 2'                             "band 2 does not count login's rounds"
has b/inflight.html 'round 1'                             "band 2 does not count signup's rounds"
has b/inflight.html '▸ send the mail'                     "band 2 does not show the first UNCHECKED checklist item"
hasnt b/inflight.html '▸ token table'                     "band 2 shows an item that is already checked off"
has b/inflight.html 'Bash: yarn test --run'               "band 2 does not show the last tool call"
has b/inflight.html '<i>ab12cd34</i>'                     "band 2 does not say which session the tool call came from"
has b/inflight.html '1/3'                                 "band 2 does not show checklist progress"
has b/inflight.html '>unapproved<'                        "band 2 does not flag signup's unapproved checklist"
hasnt b/inflight.html 'legacy'                            "band 2 shows a slice whose newest row is not dispatched"
hasnt b/inflight.html 'deadbeef'                          "band 2 treats a 5-minute-old heartbeat as live"

# band 4 — the ledger and the proof gallery, still working
has b/runs.html 'data-slice="legacy"'                     "band 4 (the ledger) lost its rows"
has b/runs.html 'finished long ago'                       "band 4 does not show the ledger notes"
has b/proof.html '/proof/login/shot.png'                  "band 4 does not show the proof screenshot"

# band 5 — grouped by path, newest first, counted, the memory write called out
has b/knowledge.html '--- knowledge name=Knowledge size=l count=2' "band 5 is not a full-width band with 2 paths"
has b/knowledge.html '3 writes · 2 paths · <b class="out">1 outside the repo</b>' "band 5 does not summarise the log"
has b/knowledge.html '>outside repo<'                     "band 5 does not mark the write outside the repo"
has b/knowledge.html '<b>MEMORY.md</b>'                   "band 5 does not show the memory path"
has b/knowledge.html '×2'                                 "band 5 does not count writes per path"
has b/knowledge.html 'write/edit'                         "band 5 does not show which tools wrote"
has b/knowledge.html '0001-magic-links.md | 1 +'          "band 5 does not carry the git summary"
python3 - "$T/b/knowledge.html" <<'EOF' || fail "band 5 is not newest first"
import sys
h = open(sys.argv[1]).read()
assert h.index("MEMORY.md") < h.index("0001-magic-links.md")
EOF

# the checklist panel — the current slice is the ledger's last line, as gate-check.sh reads it
has b/checklist.html '--- checklist name=Checklist · login'   "the checklist panel is not on the slice in flight"
has b/checklist.html 'let a user sign in with a magic link'   "the checklist panel does not show the intent"
has b/checklist.html '>gated<'                                "the checklist panel does not say it is gated"
has b/checklist.html 'approved '                              "the checklist panel does not show approved_at"
has b/checklist.html '⚑ guarded:src/shared/auth/can.ts'       "the checklist panel does not show which triggers fired"
has b/checklist.html 'proof: migration output pasted in the PR' "the checklist panel does not show each item's proof"
has b/checklist.html 'cl-i on'                                "the checklist panel does not mark a checked item"
has b/checklist.html '1/3 done'                               "the checklist panel does not show progress"

# the bands are the default layout, urgency descending, with the terminal as band 3
python3 - "$MC/js/state.js" <<'EOF' || fail "default layout is not the five bands"
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'DEFAULT_OPEN\s*=\s*\[([^\]]*)\]', src)
assert m, "no DEFAULT_OPEN"
order = [x.strip().strip('"\'') for x in m.group(1).split(",") if x.strip()]
assert order == ["gates", "inflight", "runs", "proof", "knowledge"], order
assert re.search(r'TERM_BAND\s*=\s*2', src), "the terminal band is not slot 2"
assert "splice(TERM_BAND,0,terms[0])" in src.replace(" ", ""), "the first terminal is not inserted at the terminal band"
EOF

# PROTOCOL.md is the contract between the agent layer, the runtime and the cockpit: an
# /api/state field or a route that is not in it does not exist as far as anyone else knows.
python3 - "$HERE/../../PROTOCOL.md" <<'EOF' || fail "PROTOCOL.md does not document the additions"
import re, sys
doc = open(sys.argv[1]).read()
http = doc[doc.index("## HTTP"):]
missing = [t for t in ("`checklist`", "`knowledge`", "`handoff_mtime`", "/api/machine",
                       "outside", "diffstat", "detached") if t not in http]
assert not missing, f"PROTOCOL.md HTTP section is missing: {missing}"
EOF

echo "PASS test_cockpit_bands"
