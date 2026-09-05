// front.js — the one screen and the pill. The page has no state of its own: /api/front on load
// and on every /events nudge; the loop's stream at 127.0.0.1:8790 for the Talk column, the orb and
// the title bar. The pill is this same module against pill.html at 44 px.
import { makeOrb } from "/js/orb.js";
const $ = s => document.querySelector(s), esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
try { if (localStorage.getItem("dm2-theme") === "light") document.documentElement.setAttribute("data-theme", "light"); } catch {}
// the pill asks for itself in the script tag (/js/front.js?pill=1), so read that query too; the
// page's own query wins, which is how ?voice= picks a port.
const Q = new URLSearchParams(new URL(import.meta.url).search);
for (const [k, v] of new URLSearchParams(location.search)) Q.set(k, v);
const PILL = Q.get("pill") === "1";
const VOICE = "http://127.0.0.1:" + (Q.get("voice") || "8790");
const WORDS = { idle: "listening for your name", listening: "listening", thinking: "working on it", speaking: "speaking, say anything to interrupt", waiting: "waiting on you", muted: "not listening, /dnd is on", offline: "the voice loop is off" };
const SHORT = { idle: "idle", listening: "listening", thinking: "thinking", speaking: "speaking", waiting: "waiting on you", muted: "not listening", offline: "off" };
const orb = makeOrb($("#orb"));

// ---- the loop's stream: orb, state word, title bar, Talk column, pill line ----
let es = null, youEl = null, youOpen = false, janusEl = null, lastKind = null, about = null;
function bubble(kind) { const d = document.createElement("div"); d.className = "msg " + kind; $("#talk").appendChild(d); $("#talk").scrollTop = 1e9; return d; }
function onEvent(e) {
  orb.on(e);
  if (e.t === "state") {
    document.querySelectorAll(".stateword").forEach(el => { el.textContent = SHORT[e.state] || e.state; el.dataset.s = e.state; });
    if (!PILL) { $("#barword").textContent = WORDS[e.state] || e.state; $("#bardot").dataset.s = e.state; }
    about = e.state === "waiting" ? (e.about || null) : null; markCards();
    if (PILL && ["idle", "waiting", "muted", "offline"].includes(e.state)) $("#pilltext").textContent = WORDS[e.state];
  } else if (e.t === "you") {
    if (PILL) { $("#pilltext").textContent = "“" + e.text + (e.final ? "”" : "…"); return; }
    if (!youOpen) { youEl = bubble("you"); youOpen = true; }
    youEl.textContent = e.text; youEl.classList.toggle("partial", !e.final); if (e.final) youOpen = false; lastKind = "you";
  } else if (e.t === "janus") {
    if (PILL) { if (e.text) $("#pilltext").textContent = e.text; return; }
    if (e.sentences && !e.spoken) { const d = bubble("it"); d.textContent = e.sentences.join(" "); if (e.via) d.insertAdjacentHTML("beforeend", ` <span class="seat">from ${esc(e.via)}${/alt|shop|landing|web-app/i.test(e.via) ? ", office seat" : ""}</span>`); lastKind = "janus"; return; }
    if (e.sentences) return;                              // spoken replies arrive sentence by sentence below
    if (e.bridge) { const d = bubble("it"); d.textContent = e.text; d.classList.add("bridge"); lastKind = "janus"; return; }
    if (!janusEl || lastKind !== "janus") { janusEl = bubble("it"); janusEl.dataset.reply = e.reply || ""; }
    const s = document.createElement("span"); s.textContent = (janusEl.childNodes.length ? " " : "") + e.text; janusEl.appendChild(s); lastKind = "janus"; $("#talk").scrollTop = 1e9;
  }
}
function connect() {
  es = new EventSource(VOICE + "/stream");
  es.onmessage = m => { try { onEvent(JSON.parse(m.data)); } catch {} };
  es.onerror = () => { onEvent({ t: "state", state: "offline" }); es.close(); setTimeout(connect, 5000); };
}
connect();
if (!PILL) $("#talkbox").addEventListener("submit", async ev => {
  ev.preventDefault(); const text = $("#say").value.trim(); if (!text) return; $("#say").value = "";
  try { await fetch(VOICE + "/say", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text }) }); }
  catch { await fetch("/api/front/note", { method: "POST", body: JSON.stringify({ project: FLEET, text }) }); onEvent({ t: "you", text, final: true }); }
});
// the two keys the title bar advertises. ⌥ Space is ignored while a text field has focus, so
// typing a space in the Talk box does not start the mic.
if (!PILL) document.addEventListener("keydown", e => {
  if (e.metaKey && e.key === ".") fetch(VOICE + "/stop", { method: "POST" });
  else if (e.altKey && e.code === "Space" && !/^(INPUT|TEXTAREA)$/.test(document.activeElement?.tagName)) { e.preventDefault(); fetch(VOICE + "/listen", { method: "POST" }); }
});

// ---- the fleet: rail, now, cards, employees, from /api/front on every nudge ----
let FLEET = "fleet", DATA = null;
const stripe = { waiting: "wait", building: "work", paused: "idle", stopped: "idle", idle: "ok" };
const sub = m => m.state === "waiting" ? `waiting on you · ${m.items.length} ${m.items.length === 1 ? "card" : "cards"}` : m.state === "building" ? `building · ${m.last.slice}` : m.state === "paused" ? "paused" : m.state === "stopped" ? "stopped" : m.last ? `idle · ${m.last.slice} ${m.last.status}` : "idle";
const headline = (m, r) => `${m.project} · ${r.slice} · ${r.agent.replace(/^dm-/, "")} ${r.status} · ${(r.note || "").slice(0, 120)}`;
function render(d) {
  DATA = d; FLEET = d.fleet;
  $("#rail").innerHTML = d.machines.map(m => `<div class="m ${stripe[m.state]}" data-project="${esc(m.project)}"><div class="mn">${esc(m.project)}${m.seat === "office" ? ' <span class="seat">office</span>' : ""}</div><div class="ms">${esc(sub(m))}</div></div>`).join("");
  document.querySelectorAll("#rail .m").forEach(el => el.addEventListener("click", () => openDrawer(el.dataset.project)));
  const brief = d.machines.find(m => m.project === d.fleet)?.replies?.[0];
  const fresh = brief && (Date.now() - new Date(brief.mtime.replace(" ", "T")).getTime()) < 3600e3;
  const lines = d.machines.flatMap(m => m.runs.slice(-1).map(r => headline(m, r))).slice(0, 3);
  $("#now").innerHTML = fresh ? `<p>${esc(brief.body.replace(/^(via|speak|needs|from): .*\n/gm, "")).slice(0, 1200)}</p>` : lines.length ? lines.map(l => `<p>${esc(l)}</p>`).join("") : "<p>Nothing is moving.</p>";
  const cards = d.machines.flatMap(m => m.items.map(it => ({ m, it })));
  $("#cards").innerHTML = cards.length ? cards.map(({ m, it }) => {
    const gate2 = /^gate-.*-proof\.txt$/.test(it.name), title = (it.body.split("\n")[0] || it.name).replace(/^GATE \d+ — /, "");
    const video = gate2 && m.video ? `<video controls preload="metadata" src="/api/front/proof?project=${esc(m.project)}&file=${esc(m.video)}"></video>` : "";
    return `<div class="card" data-card="${esc(m.project)}/${esc(it.name)}"><div class="ch"><span class="tag">${it.name.startsWith("ask-") ? "QUESTION" : gate2 ? "GATE 2" : "GATE 1"}</span>${esc(m.project)} · ${esc(title)}</div>
      <div class="cb">${video ? `<div class="vid">${video}</div>` : ""}<div><pre class="body">${esc(it.body.slice(0, 1500))}</pre>
      <p class="dim">${m.review ? `<a href="/api/front/proof?project=${esc(m.project)}&file=${esc(m.review)}" target="_blank">read the reviewer's guide</a> · ` : ""}${m.checklist ? `checklist ${m.checklist.done} of ${m.checklist.total} · ` : ""}<a href="#" data-open="${esc(m.project)}|${esc(m.last?.slice || "")}">open in VS Code</a></p>
      <div class="btns"><button class="btn p" data-reply="${esc(m.project)}|${esc(it.name)}|APPROVE">Approve${gate2 ? " and merge" : ""}</button><button class="btn" data-reply="${esc(m.project)}|${esc(it.name)}|REJECT">Reject with a note</button></div></div></div></div>`;
  }).join("") : `<p class="dim">Nothing waits on you.</p>`;
  document.querySelectorAll("[data-reply]").forEach(b => b.addEventListener("click", async () => {
    const [project, re, verb] = b.dataset.reply.split("|"); let text = verb;
    if (verb === "REJECT") { const note = prompt("What should change?"); if (note === null) return; text = "REJECT: " + note; }
    await fetch("/api/front/reply", { method: "POST", body: JSON.stringify({ project, re, text }) });
  }));
  document.querySelectorAll("[data-open]").forEach(a => a.addEventListener("click", async e => { e.preventDefault(); const [project, slice] = a.dataset.open.split("|"); await fetch("/api/front/open", { method: "POST", body: JSON.stringify({ project, slice }) }); }));
  $("#emp").innerHTML = d.reports.length ? d.reports.map(r => `<div><b>${esc(r.name)}</b>${esc(r.line)}</div>`).join("") : `<div class="dim">No employees yet.</div>`;
  markCards();
}
function markCards() { document.querySelectorAll(".card").forEach(c => c.classList.toggle("needs", !!about && c.dataset.card.endsWith("/" + about))); }
async function load() { try { render(await (await fetch("/api/front")).json()); } catch {} }
if (!PILL) { load(); const ev = new EventSource("/events"); ev.onmessage = m => { if (m.data === "change") load(); }; setInterval(load, 30000); }

// ---- depths two and three: the machine's own cockpit, then its terminal, in a drawer ----
function openDrawer(project) {
  const m = DATA?.machines.find(x => x.project === project); if (!m) return;
  $("#drawername").textContent = project; $("#drawer").hidden = false;
  const cockpit = `http://localhost:${m.port}/`, term = m.ttyd_port ? `http://127.0.0.1:${m.ttyd_port}/?arg=claude` : cockpit;
  $("#drawerframe").src = cockpit; $("#drawerterm").onclick = () => { $("#drawerframe").src = $("#drawerframe").src === term ? cockpit : term; };
}
if (!PILL) { $("#drawerclose").onclick = () => { $("#drawer").hidden = true; $("#drawerframe").src = "about:blank"; }; document.addEventListener("keydown", e => { if (e.key === "Escape") $("#drawerclose").click(); }); }
