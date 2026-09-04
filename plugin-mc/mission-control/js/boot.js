// Entry point. The page starts empty, fetches /api/state, renders, and re-renders on every
// /events nudge — the same path every update after first paint already took. Nothing is
// injected into this file; the server serves it as-is.
import { $, esc, rel } from "./util.js";
import { app, store, post, asks } from "./state.js";
import { rebuild } from "./grid.js";
import { drawStream, redrawDrawer, toggleDrawer } from "./drawer.js";
import "./theme.js";
import "./palette.js";

// the two back-edges the leaf modules need (see state.js)
app.rebuild = rebuild;
app.refresh = refresh;

/* ---------------- top bar ---------------- */
function render(s){
  const ae = document.activeElement;
  if (ae && (ae.tagName==="TEXTAREA" || (ae.tagName==="INPUT" && ae.type==="text"))) return; // never clobber typing
  app.S = s; app.project = s.project;
  document.body.classList.remove("offline"); $("pdot").classList.remove("down");
  $("proj").textContent = s.project;
  $("acct").textContent = s.account ? (s.account.email || s.account.dir) +
    (s.account.org && s.account.email && !s.account.org.includes(s.account.email) ? " · " + s.account.org : "") : "";
  $("usage").innerHTML = (s.usage||[]).map(u => {
    const pct = v => v==null ? "—" : v+"%";
    const cls = u.hr5>=95 ? "bad" : u.hr5>=80 ? "warn" : "";   // the 5h window is what stalls a run
    return `<span class="pill" data-tip="Usage of this session's account: 5-hour window ${pct(u.hr5)}, 7-day ${pct(u.day7)}">${esc(u.window)} · ctx ${pct(u.context)} · 5h <span class="${cls}">${pct(u.hr5)}</span>${u.cost!=null?" · $"+u.cost.toFixed(2):""}</span>`;
  }).join("");
  const working = (s.runs||[])[0];
  $("stateTxt").textContent = asks(s).length ? asks(s).length+" waiting on you" :
    working && working.status==="working" ? working.agent+" working" : "idle · "+new Date(s.now).toLocaleTimeString([], {hour:"2-digit",minute:"2-digit"});
  $("svcDots").innerHTML = (s.tmux||[]).map(w=>`<i title="${esc(w.window)}"></i>`).join("") || '<i class="b" title="not running"></i>';
  $("fleetPop").innerHTML = (s.fleet||[]).map(f =>
    `<a href="http://localhost:${f.port}" class="${f.project===s.project?"me":""}">
       <span>${esc(f.project)}</span>
       <span class="fp-r">${f.waiting ? `<i class="fp-w">${f.waiting}</i>` : ""}:${f.port}</span></a>`).join("");
  // a switcher names what is currently selected; the machine you are on is the useful label,
  // not how many exist. Other machines that want you show as a dot, so the count that matters
  // is the one you can act on.
  // MACHINE: how stale the resume point is. dm-stop.sh writes the handoff first, so a fresh
  // age is also the proof that a stop or pause completed; the registry state names it outright.
  const me = (s.fleet||[]).find(f => f.project === s.project) || {};
  const age = s.handoff_mtime ? "handoff " + rel(s.handoff_mtime) : "no handoff yet";
  $("handoffAge").textContent = me.state ? me.state + " · " + age : age;
  $("machineBtn").dataset.tip = s.handoff_mtime
    ? "Machine · handoff written " + rel(s.handoff_mtime) + " ago — pause or stop"
    : "Machine · no handoff yet — pause or stop";
  $("handoffWhen").textContent = s.handoff_mtime
    ? "handoff " + new Date(s.handoff_mtime).toLocaleString() : "no handoff written yet";
  const elsewhere = (s.fleet||[]).filter(f => f.project !== s.project && f.waiting).length;
  $("fleetName").innerHTML = esc(s.project || "fleet") + (elsewhere ? ` <i class="fp-dot"></i>` : "");
  $("fleetBtn").dataset.tip = elsewhere
    ? `${elsewhere} other machine${elsewhere>1?"s":""} waiting on you`
    : "Every machine on this host";
  rebuild();
  redrawDrawer(s);
  try { localStorage.setItem("dm2-lastseen", s.now); } catch {}
}
function offline(){ document.body.classList.add("offline"); $("pdot").classList.add("down");
  let t=null; try{ t = localStorage.getItem("dm2-lastseen"); }catch{}
  if (t) $("lastseen").textContent = "last seen "+new Date(t).toLocaleString(); }
async function refresh(){ try { render(await (await fetch("/api/state")).json()); } catch { offline(); } }

/* ---------------- composer + fleet menu ---------------- */
function wireComposer(ta, btn){
  const send = async () => { const t = $(ta).value.trim(); if (!t) return;
    $(ta).value = ""; await post("/api/inbox", { kind:"note", text:t }); toggleDrawer(true); };
  $(btn).onclick = send;
  $(ta).addEventListener("keydown", e => { if (e.key==="Enter" && !e.shiftKey){ e.preventDefault(); send(); } });
}
wireComposer("ta","sendBtn"); wireComposer("ta2","sendBtn2");
$("newSess").onclick = async () => { $("newSess").disabled = true;
  try { const r = await (await fetch("/api/session", {method:"POST"})).json();
    if (r.ok){ app.layout.open.push("term:"+r.window); app.layout.order.push("term:"+r.window); store.save(app.layout); }
  } finally { $("newSess").disabled = false; refresh(); } };
const popover = (btn, pop) => $(btn).onclick = e => { e.stopPropagation();
  document.querySelectorAll(".fleetpop.open").forEach(p => { if (p.id !== pop) p.classList.remove("open"); });
  $(pop).classList.toggle("open"); };
popover("fleetBtn", "fleetPop"); popover("machineBtn", "machinePop");
addEventListener("click", e => document.querySelectorAll(".fleetpop.open")
  .forEach(p => { if (!p.parentElement.contains(e.target)) p.classList.remove("open"); }));

// Stop and pause run dm-stop.sh on the server. Stop kills the tmux session this page's
// server lives in, so the confirmation arrives and then the page goes offline — that is the
// success path, not a failure, and the offline panel says how to bring it back.
async function machine(action){
  const ok = confirm(action === "stop"
    ? "Stop this machine?\n\nThe handoff is written, services are stopped and the tmux session is killed. Files, ledger and branches are untouched — dm.sh brings it back."
    : "Pause this machine?\n\nThe handoff is written and services are stopped. The session and the ledger stay up.");
  if (!ok) return;
  $("machinePop").classList.remove("open");
  $("handoffAge").textContent = action === "stop" ? "stopping…" : "pausing…";
  try {
    const r = await (await fetch("/api/machine", { method:"POST", headers:{"content-type":"application/json"},
      body: JSON.stringify({ action }) })).json();
    $("handoffAge").textContent = r.ok ? (action === "stop" ? "stopped" : "paused") : "failed: " + (r.error||"");
  } catch { $("handoffAge").textContent = "no reply from the server"; }
}
$("pauseBtn").onclick = () => machine("pause");
$("stopBtn").onclick  = () => machine("stop");

/* ---------------- main loop ---------------- */
refresh();
const es = new EventSource("/events");
es.onmessage = refresh; es.onerror = offline;
setInterval(() => { if (document.body.classList.contains("offline")) refresh(); }, 4000);
