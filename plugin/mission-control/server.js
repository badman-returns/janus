#!/usr/bin/env node
// Mission control — zero-dependency live dashboard over the machine's own files.
// It holds no state: everything is read fresh from the project on every request.
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const arg = (name, dflt) => {
  const i = process.argv.indexOf("--" + name);
  return i > -1 ? process.argv[i + 1] : dflt;
};
const PORT = parseInt(arg("port", "5501"), 10);
const PROJ_DIR = path.resolve(arg("project", "."));
const SESSION = arg("session", "dm-" + path.basename(PROJ_DIR));
const REGISTRY = path.join(process.env.HOME, ".delivery-machine", "registry.json");

const sh = (cmd) => {
  try { return execSync(cmd, { cwd: PROJ_DIR, timeout: 4000, stdio: ["ignore", "pipe", "ignore"] }).toString().trim(); }
  catch { return ""; }
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
  const proofDirs = listDir(path.join(PROJ_DIR, "proof")).filter(e => e.dir).map(e => ({
    slice: e.name, mtime: e.mtime,
    files: listDir(path.join(PROJ_DIR, "proof", e.name)).filter(f => !f.dir),
    readme: readIf(path.join(PROJ_DIR, "proof", e.name, "README.md")),
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
  const actRaw = readIf(path.join(PROJ_DIR, ".delivery", "activity.jsonl"), 30000) || "";
  const activity = actRaw.split("\n").filter(Boolean).slice(-20).reverse().map(l => {
    try { return JSON.parse(l); } catch { return { detail: l }; }
  });
  let registry = {};
  try { registry = JSON.parse(fs.readFileSync(REGISTRY, "utf8")); } catch {}
  let projName = path.basename(PROJ_DIR);
  try { projName = JSON.parse(fs.readFileSync(path.join(PROJ_DIR, ".delivery", "config.json"), "utf8")).project || projName; } catch {}
  return {
    project: projName, session: SESSION, now: new Date().toISOString(),
    git: {
      branch: sh("git branch --show-current"),
      status: sh("git status --short | head -25"),
      branches: sh("git branch --no-merged 2>/dev/null | head -10"),
      log: sh("git log --oneline -8"),
    },
    tmux: sh(`tmux list-windows -t ${SESSION} -F '#W|#{pane_current_command}' 2>/dev/null`)
      .split("\n").filter(Boolean).map(l => { const [w, c] = l.split("|"); return { window: w, cmd: c }; }),
    specs: listDir(path.join(PROJ_DIR, ".planning", "specs")),
    notes: listDir(path.join(PROJ_DIR, ".planning", "notes")),
    proof: proofDirs, runs, inbox, replies, activity,
    decisions: readIf(path.join(PROJ_DIR, ".delivery", "decisions.md"), 4000),
    handoff: readIf(path.join(PROJ_DIR, ".delivery", "HANDOFF.md"), 6000),
    fleet: Object.entries(registry).map(([k, v]) => ({ project: k, ...v })),
  };
}

// --- SSE: file changes + a slow heartbeat both nudge the client to refetch
const clients = new Set();
const nudge = (() => {
  let t; return () => { clearTimeout(t); t = setTimeout(() => {
    for (const res of clients) res.write("data: change\n\n");
  }, 300); };
})();
for (const d of [".delivery", ".planning", "proof"]) {
  const p = path.join(PROJ_DIR, d);
  try { fs.watch(p, { recursive: true }, nudge); } catch {}
}
setInterval(() => { for (const res of clients) res.write("data: tick\n\n"); }, 5000);

const slug = s => (s || "note").toLowerCase().replace(/[^a-z0-9-]+/g, "-").slice(0, 40) || "note";

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
        // a reply supersedes the gate item it answers
        if (kind === "reply" && re && !re.includes("/") && !re.includes(".."))
          try { fs.unlinkSync(path.join(dir, re)); } catch {}
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
  if (url === "/api/logs") {
    const w = new URL(req.url, "http://x").searchParams.get("w") || "";
    if (!/^[\w-]+$/.test(w)) { res.writeHead(400); return res.end("bad window"); }
    const out = sh(`tmux capture-pane -p -t ${SESSION}:${w} -S -300 2>/dev/null`);
    res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
    return res.end(out || "(no output — window may not exist)");
  }
  if (url === "/") {
    res.writeHead(200, { "content-type": "text/html" });
    res.end(fs.readFileSync(path.join(__dirname, "index.html")));
  } else if (url === "/fleet") {
    res.writeHead(200, { "content-type": "text/html" });
    res.end(fs.readFileSync(path.join(__dirname, "fleet.html")));
  } else if (url === "/api/fleet") {
    let reg = {};
    try { reg = JSON.parse(fs.readFileSync(REGISTRY, "utf8")); } catch {}
    const rows = Object.entries(reg).map(([k, v]) => {
      let alive = false, waiting = 0;
      try { alive = !!execSync(`tmux has-session -t ${v.session} 2>/dev/null && echo 1`, { timeout: 2000 }).toString().trim(); } catch {}
      try { waiting = fs.readdirSync(path.join(v.dir, ".delivery", "inbox")).filter(f => !/^(reply|note)-|\.gitkeep/.test(f)).length; } catch {}
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
    const file = path.normalize(path.join(PROJ_DIR, url));
    if (!file.startsWith(path.join(PROJ_DIR, "proof"))) { res.writeHead(403); return res.end(); }
    try {
      const ext = path.extname(file).toLowerCase();
      const mime = { ".png": "image/png", ".jpg": "image/jpeg", ".gif": "image/gif", ".md": "text/plain" }[ext] || "application/octet-stream";
      res.writeHead(200, { "content-type": mime });
      res.end(fs.readFileSync(file));
    } catch { res.writeHead(404); res.end(); }
  } else { res.writeHead(404); res.end("not found"); }
}).listen(PORT, () => console.log(`mission control: http://localhost:${PORT}  (${PROJ_DIR})`));
