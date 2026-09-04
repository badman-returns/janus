#!/usr/bin/env node
// Mission control — zero-dependency live dashboard over the machine's own files.
// It holds no state: everything is read fresh from the project on every request.
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const { execSync, spawn } = require("child_process");

const arg = (name, dflt) => {
  const i = process.argv.indexOf("--" + name);
  return i > -1 ? process.argv[i + 1] : dflt;
};
const PORT = parseInt(arg("port", "5501"), 10);
const PROJ_DIR = path.resolve(arg("project", "."));
const SESSION = arg("session", "dm-" + path.basename(PROJ_DIR));
const REGISTRY = path.join(process.env.HOME, ".delivery-machine", "registry.json");
// the machine's scripts live in the janus plugin, not here — the orchestrator passes the path
const SCRIPTS = path.resolve(arg("scripts", path.join(__dirname, "..", "..", "plugin", "scripts")));
// proof may live outside the machine's root (config proof_dir, e.g. "../proof" when the machine runs in app/)
const PROOF = (() => { try { return path.resolve(PROJ_DIR, JSON.parse(fs.readFileSync(path.join(PROJ_DIR, ".delivery", "config.json"), "utf8")).proof_dir || "proof"); }
                       catch { return path.join(PROJ_DIR, "proof"); } })();

const THEME = JSON.parse(fs.readFileSync(path.join(__dirname, "theme.json"), "utf8"));
// theme.json is the single source: page tokens here, xterm theme via orchestrator → ttyd
function renderTokens() {
  const vars = o => Object.entries(o).map(([k, v]) => `--${k}:${v}`).join(";");
  return `:root{${vars(THEME.dark)};--sans:${THEME.font.sans};--mono:${THEME.font.mono};--fs:${THEME.font.size}px}\n` +
         `:root[data-theme="light"]{${vars(THEME.light)}}`;
}
if (process.argv.includes("--render-tokens")) { process.stdout.write(renderTokens() + "\n"); process.exit(0); }

const sh = (cmd) => {
  try { return execSync(cmd, { cwd: PROJ_DIR, timeout: 4000, stdio: ["ignore", "pipe", "ignore"] }).toString().trim(); }
  catch { return ""; }
};
// items in a project's inbox that are waiting on the operator — gates and asks, not the
// replies and notes the operator wrote. The fleet switcher and /api/fleet share this count.
const waitingIn = (dir) => {
  try {
    const ib = path.join(dir, ".delivery", "inbox");
    return fs.readdirSync(ib).filter(f => !/^(reply|note)-|\.gitkeep/.test(f)
      && fs.statSync(path.join(ib, f)).isFile()).length;
  } catch { return 0; }
};
const readIf = (p, cap) => {
  try { const s = fs.readFileSync(p, "utf8"); return cap ? s.slice(-cap) : s; }
  catch { return null; }
};
const listDir = (p) => {
  try {
    return fs.readdirSync(p).filter(f => !f.startsWith(".")).map(f => {
      const st = fs.statSync(path.join(p, f));
      return { name: f, dir: st.isDirectory(), mtime: st.mtime.toISOString().slice(0, 16).replace("T", " ") };
    }).sort((a, b) => b.mtime.localeCompare(a.mtime));
  } catch { return []; }
};

function state() {
  const proofDirs = listDir(PROOF).filter(e => e.dir).map(e => ({
    slice: e.name, mtime: e.mtime,
    files: listDir(path.join(PROOF, e.name)).filter(f => !f.dir),
    readme: readIf(path.join(PROOF, e.name, "README.md")),
  }));
  const runsRaw = readIf(path.join(PROJ_DIR, ".delivery", "runs.jsonl"), 20000) || "";
  const runs = runsRaw.split("\n").filter(Boolean).slice(-30).reverse().map(l => {
    try { return JSON.parse(l); } catch { return { note: l }; }
  });
  const inboxDir = path.join(PROJ_DIR, ".delivery", "inbox");
  const inbox = listDir(inboxDir).filter(f => !f.dir && f.name !== ".gitkeep")
    .map(f => ({ ...f, body: (readIf(path.join(inboxDir, f.name)) || "").slice(0, 500) }));
  const repliesDir = path.join(PROJ_DIR, ".delivery", "replies");
  const replies = listDir(repliesDir).filter(f => !f.dir)
    .map(f => ({ ...f, body: (readIf(path.join(repliesDir, f.name)) || "").slice(0, 2000) }));
  const threadsDir = path.join(PROJ_DIR, ".delivery", "threads");
  const threads = listDir(threadsDir).filter(f => f.name.endsWith(".md")).map(f => {
    const full = readIf(path.join(threadsDir, f.name)) || "";
    return { name: f.name, rounds: (full.match(/^## .* · gate$/gm) || []).length, body: full.slice(-6000) };
  });
  const actRaw = readIf(path.join(PROJ_DIR, ".delivery", "activity.jsonl"), 30000) || "";
  const activity = actRaw.split("\n").filter(Boolean).slice(-20).reverse().map(l => {
    try { return JSON.parse(l); } catch { return { detail: l }; }
  });
  const agentsDir = path.join(PROJ_DIR, ".delivery", "agents");
  const now = Date.now();
  const agents = listDir(agentsDir).filter(f => f.name.endsWith(".json")).map(f => {
    try {
      const a = JSON.parse(fs.readFileSync(path.join(agentsDir, f.name), "utf8"));
      const age = (now - new Date(a.ts).getTime()) / 1000;
      return { ...a, alive: age < 120, idle: age >= 120 && age < 1800, ageSec: Math.round(age) };
    } catch { return null; }
  }).filter(Boolean).filter(a => a.ageSec < 1800).sort((x, y) => x.ageSec - y.ageSec);
  // Does any git repo track this path? Memoized per request — the same path repeats in the log,
  // and each miss is a subprocess. `--show-toplevel` from the file's own directory finds a parent
  // repo, which is the case a project-root test gets wrong.
  const trackedCache = new Map();
  const untracked = p => {
    if (trackedCache.has(p)) return trackedCache.get(p);
    const abs = path.resolve(PROJ_DIR, p);
    let out = true;
    try {
      const dir = fs.existsSync(abs) && fs.statSync(abs).isDirectory() ? abs : path.dirname(abs);
      out = !execSync("git rev-parse --show-toplevel", { cwd: dir, timeout: 2000, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    } catch { out = true; }   // not a repo, or the directory is gone: no trace either way
    trackedCache.set(p, out);
    return out;
  };
  // what each gated slice promised (.delivery/checklist/<slice>.json), newest file first.
  // Every slice, not just one: the in-flight band joins these against the ledger by name.
  const clDir = path.join(PROJ_DIR, ".delivery", "checklist");
  const checklist = listDir(clDir).filter(f => f.name.endsWith(".json")).map(f => {
    try { return JSON.parse(fs.readFileSync(path.join(clDir, f.name), "utf8")); } catch { return null; }
  }).filter(Boolean);
  // knowledge.log grouped by path, newest first. `outside` is the whole reason the log exists:
  // a write that no git repo tracks leaves no other trace, so it can only be seen here.
  //
  // It deliberately does NOT mean "above the project root". A machine running in a subdirectory
  // writes to its parent repo all the time — `../programs/arc/...` is above PROJ_DIR and fully
  // versioned — and badging that the same as an untracked memory write tells the operator the
  // opposite of the truth. The question is whether SOME repo has it, so ask git.
  const kraw = readIf(path.join(PROJ_DIR, ".delivery", "knowledge.log"), 40000) || "";
  const kby = new Map();
  let kwrites = 0;
  for (const line of kraw.split("\n")) {
    const [ts, p, kind] = line.split("\t");
    if (!p || !/^\d{4}-/.test(ts || "")) continue;          // a capped read can cut the first line in half
    kwrites++;
    const g = kby.get(p) || { path: p, count: 0, last: null, kinds: [], outside: untracked(p) };
    g.count++; if (!g.last || ts > g.last) g.last = ts;
    if (kind && !g.kinds.includes(kind)) g.kinds.push(kind);
    kby.set(p, g);
  }
  const kpaths = [...kby.values()].sort((a, b) => String(b.last).localeCompare(String(a.last)));
  const kLocal = kpaths.filter(g => !g.outside).slice(0, 40)
    .map(g => "'" + path.relative(PROJ_DIR, path.resolve(PROJ_DIR, g.path)).replace(/'/g, "'\\''") + "'");
  const knowledge = { paths: kpaths, writes: kwrites,
    diffstat: kLocal.length ? sh(`git diff --stat -- ${kLocal.join(" ")} | tail -20`) : "" };
  // age of the handoff, not its body — the top bar asks "how stale is the resume point"
  let handoff_mtime = null;
  try { handoff_mtime = fs.statSync(path.join(PROJ_DIR, ".delivery", "HANDOFF.md")).mtime.toISOString(); } catch {}
  let registry = {};
  try { registry = JSON.parse(fs.readFileSync(REGISTRY, "utf8")); } catch {}
  let projName = path.basename(PROJ_DIR);
  try { projName = JSON.parse(fs.readFileSync(path.join(PROJ_DIR, ".delivery", "config.json"), "utf8")).project || projName; } catch {}
  const mine = registry[projName] || {};
  // which Claude account this machine's sessions run on: <claude_config_dir>/.claude.json
  let account = null;
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(PROJ_DIR, ".delivery", "config.json"), "utf8"));
    const dir = cfg.claude_config_dir ? cfg.claude_config_dir.replace(/^~/, process.env.HOME) : process.env.HOME;
    const oa = JSON.parse(fs.readFileSync(path.join(dir, ".claude.json"), "utf8")).oauthAccount || {};
    account = { email: oa.emailAddress || null, org: oa.organizationName || null, dir: cfg.claude_config_dir || "default" };
  } catch {}
  const tmux = sh(`tmux list-windows -t ${SESSION} -F '#W|#{pane_current_command}' 2>/dev/null`)
    .split("\n").filter(Boolean).map(l => { const [w, c] = l.split("|"); return { window: w, cmd: c }; });
  // Claude Code's own status line at the foot of each claude window:
  // "main* · Fable 5.1 · context 11% · 5hr limit 40% · 7day limit 23% · $11.88" — any field may be missing
  const usage = tmux.filter(w => w.window.startsWith("claude")).map(w => {
    const line = sh(`tmux capture-pane -p -t '${SESSION}:${w.window}'`).split("\n")
      .filter(l => /context \d+%|\d+(hr|day) limit \d+%|\$\d/.test(l)).pop();
    if (!line) return null;
    const num = re => { const m = line.match(re); return m ? +m[1] : null; };
    const words = line.trim().split(/\s+·\s+/).filter(f => !/\d+%|\$\d/.test(f));   // [branch, model]
    return { window: w.window, model: words[1] || words[0] || null, context: num(/context (\d+)%/),
             hr5: num(/5hr limit (\d+)%/), day7: num(/7day limit (\d+)%/), cost: num(/\$(\d+(?:\.\d+)?)/) };
  }).filter(Boolean);
  return {
    project: projName, session: SESSION, now: new Date().toISOString(),
    ttyd_port: mine.ttyd_port || null, account, usage,
    git: {
      branch: sh("git branch --show-current"),
      status: sh("git status --short | head -25"),
      branches: sh("git branch --no-merged 2>/dev/null | head -10"),
      log: sh("git log --oneline -8"),
    },
    tmux,
    specs: listDir(path.join(PROJ_DIR, ".planning", "specs")),
    notes: listDir(path.join(PROJ_DIR, ".planning", "notes")),
    proof: proofDirs, runs, inbox, replies, activity, agents, threads, checklist, knowledge,
    decisions: readIf(path.join(PROJ_DIR, ".delivery", "decisions.md"), 4000),
    handoff: readIf(path.join(PROJ_DIR, ".delivery", "HANDOFF.md"), 6000), handoff_mtime,
    fleet: Object.entries(registry).map(([k, v]) => ({ project: k, ...v, waiting: waitingIn(v.dir) })),
  };
}

// one slice, spec → ledger → branch → proof → decisions, every source the machine writes
function sliceStory(name) {
  const q = s => s.replace(/'/g, "'\\''");
  const lines = f => (readIf(f) || "").split("\n").filter(Boolean);
  const runs = lines(path.join(PROJ_DIR, ".delivery", "runs.jsonl"))
    .map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(r => r && r.slice === name);
  const specDir = path.join(PROJ_DIR, ".planning", "specs");
  const sf = listDir(specDir).find(f => !f.dir && f.name.includes(name));   // listDir is newest first
  const spec = sf ? { name: sf.name, path: path.join(".planning", "specs", sf.name), body: (readIf(path.join(specDir, sf.name)) || "").slice(0, 4000) } : null;
  // decisions that name the slice, or carry a D-id the ledger or the spec refers to
  const dids = new Set(((runs.map(r => r.note).join(" ") + " " + (spec ? spec.body : "")).match(/\bD-\d+\b/g) || []));
  const decisions = lines(path.join(PROJ_DIR, ".delivery", "decisions.md"))
    .filter(l => l.includes(name) || [...dids].some(d => new RegExp("\\b" + d + "\\b").test(l)));
  const bname = sh("git for-each-ref --format='%(refname:short)' refs/heads").split("\n")
    .find(b => b === name || b.endsWith("/" + name)) || null;
  const commits = bname ? sh(`git log -20 --format='%h|%s|%cI' '${q(bname)}'`).split("\n").filter(Boolean)
    .map(l => { const [sha, subject, when] = l.split("|"); return { sha, subject, when }; }) : [];
  const pdir = path.join(PROOF, name);
  const proof = { dir: path.relative(PROJ_DIR, pdir), files: listDir(pdir).filter(f => !f.dir).map(f => f.name),
                  readme: (readIf(path.join(pdir, "README.md")) || "").slice(0, 4000) || null };
  const mentions = (dir, kind) => listDir(dir).filter(f => !f.dir).map(f => ({ name: f.name, kind, body: (readIf(path.join(dir, f.name)) || "").slice(0, 2000) }))
    .filter(f => f.name.includes(name) || f.body.includes(name));
  const gates = [...mentions(path.join(PROJ_DIR, ".delivery", "inbox"), "inbox"), ...mentions(path.join(PROJ_DIR, ".delivery", "threads"), "thread")];
  let checklist = null;
  try { checklist = JSON.parse(readIf(path.join(PROJ_DIR, ".delivery", "checklist", name + ".json"))); } catch {}
  return { slice: name, runs, spec, decisions, branch: { name: bname, commits }, proof, gates, checklist };
}

// --- SSE: file changes + a slow heartbeat both nudge the client to refetch
const clients = new Set();
const nudge = (() => {
  let t; return () => { clearTimeout(t); t = setTimeout(() => {
    for (const res of clients) res.write("data: change\n\n");
  }, 300); };
})();
for (const p of [path.join(PROJ_DIR, ".delivery"), path.join(PROJ_DIR, ".planning"), PROOF]) {
  try { fs.watch(p, { recursive: true }, nudge); } catch {}
}
setInterval(() => { for (const res of clients) res.write("data: tick\n\n"); }, 5000);

const slug = s => (s || "note").toLowerCase().replace(/[^a-z0-9-]+/g, "-").slice(0, 40) || "note";

// --- static assets: the page's stylesheet, theme.json and ES modules. Two gates, both needed:
// the url must name one of these three shapes, and the resolved path must still be inside
// __dirname — so no traversal, and nothing else in this directory (server.js included) is served.
const STATIC = { ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                 ".json": "application/json; charset=utf-8" };
const staticAsset = (url) => {
  if (!/^\/(?:[\w-]+\.css|theme\.json|js\/[\w-]+(?:\/[\w-]+)?\.js)$/.test(url) || url.includes("..")) return null;
  const file = path.normalize(path.join(__dirname, url));
  return file.startsWith(__dirname + path.sep) && STATIC[path.extname(file)] ? file : null;
};

http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  if (req.method === "POST" && url === "/api/inbox") {
    let body = "";
    req.on("data", c => { body += c; if (body.length > 10000) req.destroy(); });
    req.on("end", () => {
      try {
        const { kind, re, text } = JSON.parse(body);
        const dir = path.join(PROJ_DIR, ".delivery", "inbox");
        fs.mkdirSync(dir, { recursive: true });
        const ts = Date.now();
        let name, content;
        if (kind === "reply") {
          name = `reply-${ts}-${slug(re)}.txt`;
          content = `RE: ${re}\n${text}`;
        } else {
          name = `note-${ts}-${slug(text.slice(0, 30))}.txt`;
          content = text;
        }
        fs.writeFileSync(path.join(dir, name), content);
        // a reply supersedes the gate item it answers; a gate's exchange is kept in its thread so a
        // rejection and the revised gate that follows stay together
        if (kind === "reply" && re && !re.includes("/") && !re.includes("..")) {
          const gate = re.startsWith("gate-") ? readIf(path.join(dir, re)) : null;
          if (gate !== null) {
            const tdir = path.join(PROJ_DIR, ".delivery", "threads"), t = new Date().toISOString();
            fs.mkdirSync(tdir, { recursive: true });
            fs.appendFileSync(path.join(tdir, re.replace(/\.txt$/, "") + ".md"), `## ${t} · gate\n\n${gate.trim()}\n\n## ${t} · reply\n\n${text}\n\n`);
          }
          try { fs.unlinkSync(path.join(dir, re)); } catch {}
        }
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ ok: true, name }));
      } catch (e) {
        res.writeHead(400, { "content-type": "application/json" });
        res.end(JSON.stringify({ ok: false, error: String(e.message) }));
      }
    });
    return;
  }
  if (req.method === "POST" && url === "/api/replies/dismiss") {
    let body = "";
    req.on("data", c => { body += c; if (body.length > 2000) req.destroy(); });
    req.on("end", () => {
      try {
        const { name } = JSON.parse(body);
        if (!name || name.includes("/") || name.includes("..")) throw new Error("bad name");
        fs.unlinkSync(path.join(PROJ_DIR, ".delivery", "replies", name));
        res.writeHead(200, { "content-type": "application/json" }); res.end('{"ok":true}');
      } catch (e) { res.writeHead(400); res.end(String(e.message)); }
    });
    return;
  }
  if (req.method === "POST" && url === "/api/session") {
    // a new Claude inside the machine; same script dm.sh uses
    const w = sh(`bash '${path.join(SCRIPTS, "dm-session.sh")}'`);
    res.writeHead(w ? 200 : 500, { "content-type": "application/json" });
    return res.end(JSON.stringify(w ? { ok: true, window: w } : { ok: false, error: "could not start session" }));
  }
  if (req.method === "POST" && url === "/api/machine") {
    let body = "";
    req.on("data", c => { body += c; if (body.length > 2000) req.destroy(); });
    req.on("end", () => {
      const { action } = (() => { try { return JSON.parse(body); } catch { return {}; } })();
      if (action !== "stop" && action !== "pause") {
        res.writeHead(400, { "content-type": "application/json" });
        return res.end(JSON.stringify({ ok: false, error: "action must be stop or pause" }));
      }
      // dm-stop.sh kills the tmux session this server runs inside, so a plain execSync here
      // dies mid-response and the operator sees a network error instead of a confirmation.
      // Two things keep that from happening: the response is flushed FIRST (res.end's
      // callback fires when the body has left this process), and the script is then started
      // detached — spawn({detached:true}) setsid()s it into its own process group, so the
      // signal tmux sends to this pane's group never reaches it. The extra second is slack
      // for the socket, not for correctness.
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, action, note: "machine is going down; this page will go offline" }), () => {
        const q = str => str.replace(/'/g, "'\\''");
        const cmd = `sleep 1; exec bash '${q(path.join(SCRIPTS, "dm-stop.sh"))}'`
                  + (action === "pause" ? " --pause" : "");
        const child = spawn("/bin/bash", ["-c", cmd],
          { cwd: PROJ_DIR, detached: true, stdio: "ignore" });
        child.unref();
      });
    });
    return;
  }
  if (req.method === "POST" && url === "/api/service") {
    let body = "";
    req.on("data", c => { body += c; if (body.length > 2000) req.destroy(); });
    req.on("end", () => {
      try {
        const { window: w, action } = JSON.parse(body);
        if (!/^[\w-]+$/.test(w)) throw new Error("bad window");
        let cfg = {}; try { cfg = JSON.parse(fs.readFileSync(path.join(PROJ_DIR, ".delivery", "config.json"), "utf8")); } catch {}
        const cmd = (cfg.services || {})[w];
        const has = execSync(`tmux list-windows -t ${SESSION} -F '#W' 2>/dev/null`).toString().split("\n").includes(w);
        const q = s => s.replace(/'/g, "'\\''");
        if (action === "stop") {
          if (has) execSync(`tmux send-keys -t ${SESSION}:${w} C-c`);
        } else if (action === "restart") {
          if (has) { execSync(`tmux send-keys -t ${SESSION}:${w} C-c`);
            if (cmd) execSync(`sleep 0.6; tmux send-keys -t ${SESSION}:${w} '${q(cmd)}' Enter`); }
        } else if (action === "start") {
          if (!cmd) throw new Error("no command for " + w + " in config");
          if (!has) execSync(`tmux new-window -t ${SESSION} -n ${w} -c '${q(PROJ_DIR)}'`);
          execSync(`tmux send-keys -t ${SESSION}:${w} '${q(cmd)}' Enter`);
        } else throw new Error("unknown action");
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ ok: true, window: w, action }));
      } catch (e) { res.writeHead(400, { "content-type": "application/json" }); res.end(JSON.stringify({ ok:false, error:String(e.message) })); }
    });
    return;
  }
  if (url === "/api/activity") {
    const sid = new URL(req.url, "http://x").searchParams.get("sid") || "";
    const raw = readIf(path.join(PROJ_DIR, ".delivery", "activity.jsonl"), 60000) || "";
    const rows = raw.split("\n").filter(Boolean).map(l => { try { return JSON.parse(l); } catch { return null; } })
      .filter(Boolean).filter(a => !sid || a.sid === sid).slice(-80).reverse();
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify(rows));
  }
  if (url === "/api/slice") {
    const name = new URL(req.url, "http://x").searchParams.get("name") || "";
    if (!/^[\w.-]+$/.test(name)) { res.writeHead(400); return res.end("bad name"); }
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify(sliceStory(name)));
  }
  if (url === "/api/logs") {
    const w = new URL(req.url, "http://x").searchParams.get("w") || "";
    if (!/^[\w-]+$/.test(w)) { res.writeHead(400); return res.end("bad window"); }
    const out = sh(`tmux capture-pane -p -t ${SESSION}:${w} -S -300 2>/dev/null`);
    res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
    return res.end(out || "(no output — window may not exist)");
  }
  if (url === "/" || url === "/fleet") {
    res.writeHead(200, { "content-type": "text/html" });
    res.end(fs.readFileSync(path.join(__dirname, url === "/" ? "index.html" : "fleet.html")));
  } else if (url === "/api/fleet") {
    let reg = {};
    try { reg = JSON.parse(fs.readFileSync(REGISTRY, "utf8")); } catch {}
    const rows = Object.entries(reg).map(([k, v]) => {
      let alive = false, waiting = 0;
      try { alive = !!execSync(`tmux has-session -t ${v.session} 2>/dev/null && echo 1`, { timeout: 2000 }).toString().trim(); } catch {}
      waiting = waitingIn(v.dir);
      return { project: k, ...v, alive, waiting };
    });
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(rows));
  } else if (url === "/api/state") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(state()));
  } else if (url === "/events") {
    res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
    res.write("data: hello\n\n");
    clients.add(res);
    req.on("close", () => clients.delete(res));
  } else if (url.startsWith("/proof/")) {
    const file = path.normalize(path.join(PROOF, url.slice("/proof/".length)));
    if (!file.startsWith(PROOF + path.sep)) { res.writeHead(403); return res.end(); }
    const ext = path.extname(file).toLowerCase();
    const mime = { ".png": "image/png", ".jpg": "image/jpeg", ".gif": "image/gif", ".md": "text/plain" }[ext] || "application/octet-stream";
    // read before the head goes out: after writeHead a missing file cannot 404, it throws
    let bytes; try { bytes = fs.readFileSync(file); } catch { res.writeHead(404); return res.end(); }
    res.writeHead(200, { "content-type": mime });
    res.end(bytes);
  } else if (staticAsset(url)) {
    // the page's own stylesheet and ES modules, from this directory only. Tokens are
    // prepended to CSS here, so theme.json stays the single source and no page is ever
    // served with a hole in it waiting to be filled.
    let body;
    const file = staticAsset(url), ext = path.extname(file);
    // read first: a missing file must 404, and it cannot once the 200 head is out
    try { body = ext === ".css" ? renderTokens() + "\n" + fs.readFileSync(file, "utf8") : fs.readFileSync(file); }
    catch { res.writeHead(404); return res.end(); }
    res.writeHead(200, { "content-type": STATIC[ext] });
    res.end(body);
  } else { res.writeHead(404); res.end("not found"); }
}).listen(PORT, () => console.log(`mission control: http://localhost:${PORT}  (${PROJ_DIR})`));
