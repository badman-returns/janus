// NOW — IN FLIGHT. The band the ledger could never show. Every other status is written
// after the fact, so an agent thinking for ten minutes was a silence; `dispatched` is
// written before the work, and a slice whose newest ledger row is `dispatched` is an agent
// running right now. One row per running agent, joined out of three files: the ledger
// (role, slice, round, when), the heartbeats (live, last tool) and the slice's checklist
// (the first unchecked item — what it is doing, in its own words).
import { esc, rel } from "../util.js";
import { ICON } from "../icons.js";

// s.runs is newest-first, so the first row naming a slice is that slice's current state.
export function inFlight(s) {
  const runs = s.runs || [], seen = new Set(), out = [];
  const live = (s.agents || []).filter(a => a.alive);
  for (const r of runs) {
    if (!r.slice || seen.has(r.slice)) continue;
    seen.add(r.slice);
    if (r.status !== "dispatched") continue;              // a later status ended this dispatch
    const cl = (s.checklist || []).find(c => c.slice === r.slice) || null;
    const items = cl ? (cl.items || []) : [];
    // Heartbeats carry no slice and no role — activity.sh writes {sid,ts,event,detail,role,cwd}
    // where role is "session"/"spawning agent" (PROTOCOL.md). The only key on offer is the
    // directory basename, which matches for a builder in its own per-slice worktree; failing
    // that the newest live session is what is running, and its sid is shown so the operator
    // can see whose tool call this is rather than trust an invented join.
    const hb = live.find(a => a.cwd === r.slice) || live[0] || null;
    out.push({
      role: (r.agent || "agent").replace(/^dm-/, ""), slice: r.slice, ts: r.ts, note: r.note || "",
      round: runs.filter(x => x.slice === r.slice && x.status === "dispatched").length,
      item: items.find(i => !i.done) || null, done: items.filter(i => i.done).length, total: items.length,
      matched: !!(hb && hb.cwd === r.slice), hb,
      gated: cl ? !!cl.gated : null, approved: cl ? !!cl.approved_at : null,
    });
  }
  return out;
}

export default s => {
  const rows = inFlight(s);
  return { name: "Now — in flight", icon: ICON.flight, size: "l", count: rows.length || null,
    body() {
      if (!rows.length) {
        const last = (s.runs || [])[0];
        return `<div class="empty">Nothing in flight — no slice's newest ledger row is <span class="cmd">dispatched</span>.
          ${last ? `Last: <b>${esc((last.agent || "").replace(/^dm-/, ""))}</b> ${esc(last.slice || "")} — ${esc(last.status || "")} ${esc(rel(last.ts))} ago.`
                 : `The ledger is empty; give the machine an intent with <span class="cmd">/dm</span>.`}</div>`;
      }
      return rows.map(f => {
        const tool = f.hb ? (f.hb.detail || f.hb.event || "—") : null;
        return `<div class="fl">
          <span class="pill acc">${esc(f.role)}</span>
          <span class="fl-s"><a data-slice="${esc(f.slice)}" title="the whole story of this slice">${esc(f.slice)}</a></span>
          <span class="pill" title="This is dispatch ${f.round} of ${esc(f.slice)}">round ${f.round}</span>
          <span class="pill" title="Dispatched ${esc(f.ts || "")}">${esc(rel(f.ts))}</span>
          ${f.total ? `<span class="pill" title="Checklist items checked off">${f.done}/${f.total}</span>` : ""}
          ${f.gated && !f.approved ? `<span class="pill out" title="Its checklist has no approved_at — the scope gate is still shut">unapproved</span>` : ""}
          <span class="fl-i" title="${esc(f.item ? "proof: " + (f.item.proof || "") : "")}">${
            f.item ? "▸ " + esc(f.item.text)
                   : f.total ? "▸ every item checked — waiting on the verifier"
                             : "▸ no checklist declared"}</span>
          <span class="fl-t ${f.hb ? "" : "cold"}" title="${f.hb ? (f.matched
              ? "Last tool call from the session working in " + esc(f.slice)
              : "Heartbeats carry no slice, so this is the newest live session — not provably this one") : "No heartbeat under 120s: dispatched, but nothing is reporting in"}">${
            f.hb ? esc(tool) + ` <i>${esc(f.hb.sid)}</i>` : "no heartbeat"}</span></div>`;
      }).join("");
    } };
};
