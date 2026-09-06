// front.js — the one screen and the pill. The page has no state of its own: /api/front on load
// and on every /events nudge. The Talk column is that file thread (talk.jsonl joined to
// replies/<stem>.md), so it is whole with the voice loop parked; the loop's stream at
// 127.0.0.1:8790, when it answers, only lends the orb, the state word and a live transcript.
// The pill is this same module against pill.html at 44 px.
import { makeOrb } from "/js/orb.js";
import { SAFE, esc } from "/js/mdsafe.js";
const $ = s => document.querySelector(s);
try { if (localStorage.getItem("dm2-theme") === "light") document.documentElement.setAttribute("data-theme", "light"); } catch {}
// the pill asks for itself in the script tag (/js/front.js?pill=1), so read that query too; the
// page's own query wins, which is how ?voice= picks a port.
const Q = new URLSearchParams(new URL(import.meta.url).search);
for (const [k, v] of new URLSearchParams(location.search)) Q.set(k, v);
const PILL = Q.get("pill") === "1";
const VOICE = "http://127.0.0.1:" + (Q.get("voice") || "8790");
// "ready" is what a parked loop looks like: the text path does not need it, so its absence is not
// an error to report — the orb rests and the bar stays quiet.
const WORDS = { idle: "listening for your name", listening: "listening", thinking: "working on it", speaking: "speaking, say anything to interrupt", waiting: "waiting on you", muted: "not listening, /dnd is on", offline: "ready" };
const SHORT = { idle: "idle", listening: "listening", thinking: "thinking", speaking: "speaking", waiting: "waiting on you", muted: "not listening", offline: "ready" };
const orb = makeOrb($("#orb"));

// ---- the loop's stream: orb, state word, title bar, the live transcript, pill line ----
// It never writes the thread: what was said reaches the page as talk.jsonl, like what was typed.
let es = null, partial = null, about = null;
// the seat is the machine's, not the name's: /api/front derives it from claude_config_dir.
// No mark before the fleet has loaded, and none for a machine that is not registered.
const mark = (el, via) => { if (via) el.insertAdjacentHTML("beforeend", ` <span class="seat">from ${esc(via)}${DATA?.machines.find(m => m.project === via)?.seat === "office" ? ", office seat" : ""}</span>`); };
function onEvent(e) {
  orb.on(e);
  if (e.t === "state") {
    document.querySelectorAll(".stateword").forEach(el => { el.textContent = SHORT[e.state] || e.state; el.dataset.s = e.state; });
    if (!PILL) { $("#barword").textContent = WORDS[e.state] || e.state; $("#bardot").dataset.s = e.state; }
    about = e.state === "waiting" ? (e.about || null) : null; markCards();
    if (PILL && ["idle", "waiting", "muted", "offline"].includes(e.state)) $("#pilltext").textContent = WORDS[e.state];
  } else if (e.t === "you") {
    if (PILL) { $("#pilltext").textContent = "“" + e.text + (e.final ? "”" : "…"); return; }
    if (!partial) { partial = document.createElement("div"); partial.className = "msg you partial"; $("#talk").appendChild(partial); }
    partial.textContent = e.text;
    if (e.final) partial = null;                             // the journal carries it from here
    $("#talk").scrollTop = 1e9;
  } else if (e.t === "false_alarm") {                      // the mic heard only his own tail: no note, and no trace of the invented words
    if (PILL) return;                                        // the state event that follows sets the pill's text
    if (partial) partial.remove(); partial = null;
  } else if (e.t === "janus" && PILL && e.text) $("#pilltext").textContent = e.text;
}
function connect() {
  es = new EventSource(VOICE + "/stream");
  es.onmessage = m => { try { onEvent(JSON.parse(m.data)); } catch {} };
  // a parked loop is the normal case, so knock rarely and say nothing about it
  es.onerror = () => { onEvent({ t: "state", state: "offline" }); es.close(); setTimeout(connect, 30000); };
}
connect();
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
  $("#now").innerHTML = fresh ? `<p>${esc(brief.body.replace(/^(via|speak|needs|from|refs): .*\n/gm, "")).slice(0, 1200)}</p>` : lines.length ? lines.map(l => `<p>${esc(l)}</p>`).join("") : "<p>Nothing is moving.</p>";
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
  markCards(); if (!PILL) renderTalk();
}
// `needs: <machine> <file>` (PROTOCOL.md): the card is "<machine>/<file>". One token is a bare file.
function markCards() { const [p, f] = String(about || "").split(/\s+/);
  document.querySelectorAll(".card").forEach(c => c.classList.toggle("needs", !!about && (f ? c.dataset.card === p + "/" + f : c.dataset.card.endsWith("/" + p)))); }
// ---- the Talk column: the file thread, and the box that adds to it ----
if (!PILL && window.marked) marked.use({ renderer: SAFE });   // mdsafe.js: words, never markup
function md(src) {
  const d = document.createElement("div"); d.className = "md";
  d.innerHTML = window.marked ? marked.parse(String(src || "")) : esc(src).replace(/\n/g, "<br>");
  return d;
}
const when = ts => { const d = new Date(ts || ""); return isNaN(d) ? "" : d.toLocaleString(); };
const PENDING = [];   // sent, not yet in the journal: the bubble is up before the POST returns
function replyEl(rep) {
  const d = document.createElement("div"); d.className = "msg it"; d.title = when(rep.mtime);
  d.appendChild(md(rep.body));
  mark(d, rep.headers.via);
  for (const p of rep.headers.refs || []) {                  // what the answer was read out of
    const b = document.createElement("button"); b.className = "ref"; b.textContent = p; b.title = "open in VS Code";
    b.onclick = () => fetch("/api/front/open", { method: "POST", body: JSON.stringify({ project: rep.headers.via || FLEET, file: p }) });
    d.appendChild(b);
  }
  return d;
}
let sig = null;
function renderTalk() {
  const el = $("#talk"); if (!el) return;
  const rows = DATA?.talk || [];
  // a pending bubble is the journal's own line until the journal has it: same words AND written
  // no earlier than the send, so asking the same question twice keeps both bubbles
  for (let i = PENDING.length - 1; i >= 0; i--)
    if (rows.some(r => r.text === PENDING[i].text && Date.parse(r.ts) >= Date.parse(PENDING[i].ts))) PENDING.splice(i, 1);
  // every nudge lands here, most of them about something else: rebuild only when the thread moved
  const now = rows.map(r => r.stem + "@" + (r.reply?.mtime || "")).join("|") + "#" + PENDING.length;
  if (now === sig) return;
  sig = now;
  const stick = el.scrollHeight - el.scrollTop - el.clientHeight < 80;   // he scrolled up: stay there
  el.textContent = "";
  for (const r of [...rows, ...PENDING]) {
    const you = document.createElement("div"); you.className = "msg you"; you.textContent = r.text; you.title = when(r.ts);
    el.appendChild(you);
    if (r.reply) el.appendChild(replyEl(r.reply));
    else el.insertAdjacentHTML("beforeend", '<div class="msg it think"><i></i><i></i><i></i></div>');
  }
  if (partial) el.appendChild(partial);
  if (stick) el.scrollTop = 1e9;
}
if (!PILL) {
  const say = $("#say"), grow = () => { say.style.height = "auto"; say.style.height = say.scrollHeight + "px"; };
  say.addEventListener("input", () => { grow(); $("#sendfail").textContent = ""; });
  // isComposing: Enter is how an IME accepts its candidate, not how he sends
  say.addEventListener("keydown", e => { if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); $("#talkbox").requestSubmit(); } });
  say.focus();
  $("#talkbox").addEventListener("submit", async ev => {
    ev.preventDefault(); const text = say.value.trim(); if (!text) return;
    say.value = ""; grow(); $("#sendfail").textContent = "";
    const p = { ts: new Date().toISOString(), text, reply: null };
    PENDING.push(p); renderTalk();
    const r = await fetch("/api/front/note", { method: "POST", body: JSON.stringify({ project: FLEET, text }) }).catch(() => null);
    // it never reached the concierge: take the bubble back, hand him his words, say so once
    if (!r?.ok) {
      const i = PENDING.indexOf(p); if (i > -1) PENDING.splice(i, 1);
      if (!say.value) { say.value = text; grow(); }
      $("#sendfail").textContent = "not sent — the words are back in the box";
      renderTalk();
    }
    load();
  });
}
async function load() { try { render(await (await fetch("/api/front")).json()); } catch {} }
if (!PILL) { load(); const ev = new EventSource("/events"); ev.onmessage = m => { if (m.data === "change") load(); }; setInterval(load, 60000); }

// ---- depths two and three: the machine's own cockpit, then its terminal, in a drawer ----
function openDrawer(project) {
  const m = DATA?.machines.find(x => x.project === project); if (!m) return;
  $("#drawername").textContent = project; $("#drawer").hidden = false;
  const cockpit = `http://localhost:${m.port}/`, term = m.ttyd_port ? `http://127.0.0.1:${m.ttyd_port}/?arg=${encodeURIComponent("claude@" + project)}` : cockpit;
  $("#drawerframe").src = cockpit; $("#drawerterm").onclick = () => { $("#drawerframe").src = $("#drawerframe").src === term ? cockpit : term; };
}
if (!PILL) { $("#drawerclose").onclick = () => { $("#drawer").hidden = true; $("#drawerframe").src = "about:blank"; }; document.addEventListener("keydown", e => { if (e.key === "Escape") $("#drawerclose").click(); }); }
