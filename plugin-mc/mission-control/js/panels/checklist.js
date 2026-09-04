// The checklist a gated slice declared before its first edit: what will be done, and for
// each item the proof that will show it was. This is the only thing on the page that answers
// "how far along is it" — the ledger says which statuses have been reached, the checklist
// says how much of the promise is kept. `approved_at` is what gate-check.sh actually reads,
// so an unapproved checklist is not a formality: nothing can be written until it is stamped.
import { esc, rel } from "../util.js";
import { ICON } from "../icons.js";

// Shared with the slice-story drawer, which shows the checklist of the slice being read
// rather than the one in flight.
export function renderChecklist(cl) {
  if (!cl) return `<div class="empty">No checklist for this slice.</div>`;
  const items = cl.items || [], done = items.filter(i => i.done).length;
  return `<div class="cl-h">
      <p class="cl-int">${esc(cl.intent || "(no intent recorded)")}</p>
      <div class="acts" style="margin-top:8px">
        <span class="pill${cl.gated ? " acc" : ""}">${cl.gated ? "gated" : "not gated"}</span>
        <span class="pill${cl.approved_at ? "" : " out"}" title="${cl.approved_at
          ? "gate-check.sh reads this stamp and lets writes through" : "gate-check.sh reads only this stamp — writes are refused until it is set"}">${
          cl.approved_at ? "approved " + esc(rel(cl.approved_at)) + " ago" : "not approved"}</span>
        <span class="pill">${done}/${items.length} done</span>
        ${(cl.triggers || []).map(t => `<span class="pill" title="Why this slice is gated">⚑ ${esc(t)}</span>`).join("")}
      </div></div>` +
    (items.length ? items.map((i, n) => `<div class="cl-i ${i.done ? "on" : ""}">
        <span class="cl-b">${i.done ? "✓" : n}</span>
        <span class="cl-t">${esc(i.text)}
          <em>proof: ${esc(i.proof || "— none stated")}</em></span>
        <span class="when">${i.ts ? esc(rel(i.ts)) : ""}</span></div>`).join("")
      : `<div class="empty">Declared, but no items yet — <span class="cmd">checklist.sh add</span>.</div>`);
}

// The slice in flight is the one named by the ledger's last line, which is exactly what
// gate-check.sh uses; with no ledger, the newest checklist file is the only candidate.
export const currentChecklist = s => {
  const cls = s.checklist || [], slice = ((s.runs || [])[0] || {}).slice;
  return cls.find(c => c.slice === slice) || cls[0] || null;
};

export default s => {
  const cl = currentChecklist(s);
  const items = cl ? (cl.items || []) : [];
  return { name: cl ? "Checklist · " + cl.slice : "Checklist", icon: ICON.check,
    count: items.length ? `${items.filter(i => i.done).length}/${items.length}` : null,
    alert: !!(cl && cl.gated && !cl.approved_at),
    body() {
      return cl ? renderChecklist(cl)
        : `<div class="empty">No slice has declared one. Every intent writes
           <span class="cmd">.delivery/checklist/&lt;slice&gt;.json</span> before its first edit
           (<span class="cmd">checklist.sh init</span>), and each item must name what will prove it.</div>`;
    } };
};
