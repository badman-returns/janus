// The right-hand drawer: the stream by default, and on demand one agent's history or one
// slice's whole story (spec → ledger → commits → proof → decisions → gates).
import { $, esc, rel } from "./util.js";
import { app, store, asks } from "./state.js";
import { renderChecklist } from "./panels/checklist.js";

function streamItems(s){
  const items = [];
  (s.activity||[]).slice().reverse().forEach(a => items.push({ts:a.ts, who:a.event==="prompt"?"you":"session", icon:a.event==="prompt"?"🙋":"", text:a.detail||a.event, cls:a.event==="prompt"?"you":""}));
  (s.runs||[]).slice().reverse().forEach(r => items.push({ts:r.ts, who:(r.agent||"machine").replace("dm-",""), text:`${r.slice||""} — ${r.status}${r.note?" · "+r.note:""}`}));
  (s.replies||[]).forEach(r => items.push({ts:null, tsRaw:r.mtime, who:"machine", text:r.body, cls:""}));
  asks(s).forEach(i => items.push({ts:null, tsRaw:i.mtime, who:"gate", text:i.name+"\n"+i.body, cls:"gate"}));
  items.sort((a,b) => String(a.ts||a.tsRaw||"").localeCompare(String(b.ts||b.tsRaw||"")));
  return items;
}
let lastStreamCount = 0;
export function drawStream(s){
  const items = streamItems(s);
  const el = $("dscroll");
  const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 60;
  el.innerHTML = `<div class="dayrule">the story so far</div>` + (items.length ? items.map(i => `
    <div class="msg"><div class="av ${i.cls==="you"?"you":""}">${i.who==="gate"?"⚠":i.cls==="you"?"↑":"·"}</div>
      <div class="m-b"><div class="m-h"><b>${esc(i.who)}</b> ${i.ts?"· "+rel(i.ts):""}</div>
      <div class="bub ${esc(i.cls||"")}">${esc(i.text)}</div></div></div>`).join("")
    : `<div class="empty">Quiet so far. Events, gates, and replies land here as they happen.</div>`);
  if (atBottom) el.scrollTop = el.scrollHeight;
  // unread badge
  let seen = 0; try { seen = +localStorage.getItem("dm2-seen-"+app.project) || 0; } catch {}
  const n = Math.max(0, items.length - seen);
  $("unread").textContent = $("drawer").classList.contains("open") ? "" : (n || "");
  if ($("drawer").classList.contains("open")) { try { localStorage.setItem("dm2-seen-"+app.project, items.length); } catch {} }
  lastStreamCount = items.length;
}
let focusedSid = null, focusedSlice = null;
export function toggleDrawer(open){
  const d = $("drawer"), o = open ?? !d.classList.contains("open");
  d.classList.toggle("open", o); $("scrim").classList.toggle("open", o);
  if (o && app.S){ if (!focusedSid && !focusedSlice){ try { localStorage.setItem("dm2-seen-"+app.project, lastStreamCount); } catch {} drawStream(app.S); } $("ta2").focus(); }
  if (!o){ focusedSid = focusedSlice = null; }
}
function backToStream(){ focusedSid = focusedSlice = null; $("d-title").innerHTML = `<span class="name">Stream</span><span class="sub">the story, oldest → newest</span>`; drawStream(app.S); }
function drawerHead(title){ $("d-title").innerHTML = `<button class="backbtn" id="backBtn">← stream</button> <span class="name" style="margin-left:8px">${title}</span>`; $("backBtn").onclick = backToStream; }
export async function focusAgent(sid){
  focusedSid = sid; focusedSlice = null;
  toggleDrawer(true);
  drawerHead(`agent ${esc(sid)}`);
  await renderAgentHistory(sid);
}
export async function focusSlice(name){
  focusedSlice = name; focusedSid = null; renderSlice.last = null;
  toggleDrawer(true);
  drawerHead(`slice ${esc(name)}`);
  $("dscroll").innerHTML = `<div class="dayrule">loading ${esc(name)}…</div>`;
  await renderSlice(name);
}
async function renderSlice(name){
  let d; try { d = await (await fetch("/api/slice?name=" + encodeURIComponent(name))).json(); } catch { return; }
  const j = JSON.stringify(d); if (j === renderSlice.last || focusedSlice !== name) return; renderSlice.last = j;
  const el = $("dscroll"), wasOpen = new Set([...el.querySelectorAll("details[open]")].map(x => x.dataset.k));
  const runs = d.runs||[], last = runs[runs.length-1];
  const verified = runs.some(r => r.agent==="dm-verifier" && r.status==="done");
  const status = !last ? "no runs" : last.status==="done" && !verified ? (last.agent||"").replace("dm-","")+" done" : last.status;
  const row = r => `<div class="run"><span class="pill">${esc((r.agent||"").replace("dm-",""))}</span><span class="tag ${esc(r.status)}">${esc(r.status)}</span>
      <span class="what">${esc(r.note||"")}</span><span class="when">${rel(r.ts)}</span></div>`;
  const fold = (k, label, body) => `<details class="fold" data-k="${k}" ${wasOpen.has(k)?"open":""}><summary>${label}</summary><pre class="mono">${esc(body)}</pre></details>`;
  const sec = (label, body) => `<div class="dayrule">${label}</div>` + (body || `<div class="empty">none</div>`);
  const fixes = runs.filter(r => /^(reviewed|failed|fixed)$/.test(r.status));
  const p = d.proof||{}, imgs = (p.files||[]).filter(f => /\.(png|jpe?g|gif)$/i.test(f));
  const href = f => `/proof/${encodeURIComponent(name)}/${encodeURIComponent(f)}`;
  el.innerHTML = `<div class="story">
    <div class="run" style="border-top:0"><span class="tag ${verified?"done":esc(last?last.status:"")}">${esc(status)}</span>
      <span class="what">${d.branch.name ? `on <span class="path">${esc(d.branch.name)}</span>` : "no branch"}</span></div>
    ${sec("Spec", d.spec ? `<div class="path">${esc(d.spec.path)}</div>` + fold("spec", "read", d.spec.body) : "")}
    ${sec("Checklist", d.checklist ? renderChecklist(d.checklist) : "")}
    ${sec("Ledger", runs.map(row).join(""))}
    ${fixes.length ? sec("Review &amp; fixes", fixes.map(row).join("")) : ""}
    ${sec("Commits", (d.branch.commits||[]).map(c => `<div class="run"><span class="pill">${esc(c.sha)}</span><span class="what">${esc(c.subject)}</span><span class="when">${rel(c.when)}</span></div>`).join(""))}
    ${sec("Proof", (imgs.length || p.readme) ? `<div class="path">${esc(p.dir||"")}</div>
      <div class="shots">${imgs.map(f => `<a href="${href(f)}" target="_blank" rel="noopener"><img loading="lazy" src="${href(f)}" alt="${esc(f)}"></a>`).join("")}</div>
      ${p.readme ? fold("readme", "README.md", p.readme) : ""}` : "")}
    ${sec("Decisions", (d.decisions||[]).length ? `<pre class="mono">${esc(d.decisions.join("\n"))}</pre>` : "")}
    ${(d.gates||[]).length ? sec("Gates", d.gates.map(g => fold("g:"+g.name, esc(g.kind+" · "+g.name), g.body)).join("")) : ""}
  </div>`;
}
async function renderAgentHistory(sid){
  const el = $("dscroll");
  el.innerHTML = `<div class="dayrule">loading agent ${esc(sid)}…</div>`;
  let rows = [];
  try { rows = await (await fetch("/api/activity?sid=" + encodeURIComponent(sid))).json(); } catch {}
  const a = (app.S.agents||[]).find(x => x.sid === sid);
  const head = a ? `<div class="dayrule">${a.alive?"● live":a.idle?"○ idle":"○ ended"} · ${esc(a.role||"session")} · ${esc(a.cwd||"")}</div>` : "";
  el.innerHTML = head + (rows.length ? rows.map(r => `<div class="aevt">
      <span class="ev ${esc(r.event)}">${esc(r.event)}</span>
      <span class="dt">${esc(r.detail || "—")}</span>
      <time>${rel(r.ts)}</time></div>`).join("")
    : `<div class="empty">No recorded events for this agent yet.</div>`);
}
// whatever the drawer is currently showing, redrawn from a fresh /api/state
export function redrawDrawer(s){
  if (focusedSid && $("drawer").classList.contains("open")) renderAgentHistory(focusedSid);
  else if (focusedSlice && $("drawer").classList.contains("open")) renderSlice(focusedSlice);
  else drawStream(s);
}
$("streamBtn").onclick = () => toggleDrawer();
$("drawerX").onclick = () => toggleDrawer(false);
$("scrim").onclick = () => toggleDrawer(false);
// Escape closes the drawer first, then leaves focus mode
addEventListener("keydown", e => { if (e.key!=="Escape") return;
  if ($("drawer").classList.contains("open")) return toggleDrawer(false);
  if (app.layout && app.layout.focus.length){ app.layout.focus = []; store.save(app.layout); app.rebuild(); } });
