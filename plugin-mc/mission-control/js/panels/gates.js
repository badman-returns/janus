// "Waiting on you": ask cards (JSON, from the ask.sh hook), gate cards (plain text),
// the machine's replies, and the operator's own writing still awaiting pickup.
import { esc, rel } from "../util.js";
import { ICON } from "../icons.js";
import { asks, outbound } from "../state.js";
import { inFlight } from "./inflight.js";

export default s => ({ name:"Waiting on you", icon:ICON.gate, size:"l", count: asks(s).length,
  alert: asks(s).length>0 || (s.replies||[]).length>0,
  body(){ let h = "";
    // ask-* cards carry a JSON body (question + options) written by the ask.sh hook; gates are plain text
    const parsed = asks(s).map(i => { let j = null; if (i.name.startsWith("ask-")) { try { j = JSON.parse(i.body); } catch {} } return { ...i, j }; });
    h += parsed.filter(i => i.j).map(i => `<div class="item ask" data-ask="${esc(i.name)}">
      <b class="fn">${i.j.kind==="permission"?"permission":"question"} · ${esc(i.j.title||"")}</b>
      ${(i.j.questions||[]).map((q,qi) => `<p>${esc(q.question)}</p><div class="opts">
        ${(q.options||[]).map(o => `<label class="opt"><input type="${q.multi?"checkbox":"radio"}" name="q${qi}-${esc(i.name)}" value="${esc(o)}"> ${esc(o)}</label>`).join("")}
      </div>`).join("")}
      <div class="acts"><input class="note-in" placeholder="or type an answer…" data-ask-text="${esc(i.name)}">
      <button class="btn pri" data-ask-send="${esc(i.name)}">Answer</button></div></div>`).join("");
    const a = parsed.filter(i => !i.j);
    // a gate that came back after a rejection carries its earlier rounds in .delivery/threads
    const thread = i => (s.threads||[]).find(t => t.name === i.name.replace(/\.txt$/, "") + ".md");
    h += a.length ? a.map(i => `<div class="item gate"><b class="fn">${esc(i.name)}</b><p>${esc(i.body)}</p>
      <div class="acts"><button class="btn pri" data-act="approve" data-re="${esc(i.name)}">Approve</button>
      <button class="btn" data-act="reject" data-re="${esc(i.name)}">Reject</button>
      <input class="note-in" placeholder="note…" data-note-for="${esc(i.name)}"></div>
      ${thread(i) ? `<details class="thread"><summary>round ${thread(i).rounds+1} · previous rounds ↓</summary><pre>${esc(thread(i).body)}</pre></details>` : ""}</div>`).join("")
      : (parsed.length ? "" : (() => {
        const fl = inFlight(s), last = (s.runs||[])[0];
        const doing = fl.length
          ? `<b>${fl.length} agent${fl.length>1?"s":""} in flight</b> — ${esc(fl.map(f=>f.role+" on "+f.slice).join(", "))}.`
          : last ? `Nothing is running either. Last ledger row: <b>${esc((last.agent||"").replace(/^dm-/,""))}</b> ${esc(last.slice||"")} — ${esc(last.status||"")}, ${esc(rel(last.ts))} ago.`
                 : `Nothing is running either, and the ledger is empty — start with <span class="cmd">/dm</span>.`;
        return `<div class="empty"><b>Nothing is waiting on you.</b> ${doing}<br>
          A gate (the architect's plan, the verifier's proof), a question or a permission prompt
          lands here the moment it is raised, and pings your phone if
          <span class="cmd">ntfy_topic</span> is set. Until then this band stays empty on purpose.</div>`; })());
    h += (s.replies||[]).map(r => `<div class="reply-item"><button class="x" data-dismiss="${esc(r.name)}" data-tip="Dismiss" aria-label="Dismiss">${ICON.close}</button>
      <b class="fn">machine replied</b><p>${esc(r.body)}</p></div>`).join("");
    const out = outbound(s);
    h += out.map(i => `<div style="font:500 11.5px var(--mono);color:var(--mut2);padding:3px 0">↗ ${esc(i.name)} — awaiting pickup</div>`).join("");
    return h; } });
