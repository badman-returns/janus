// The ledger, newest first. A slice name is a link into its whole story (the drawer).
import { esc, rel } from "../util.js";
import { ICON } from "../icons.js";

export default s => ({ name:"Agent runs", icon:ICON.runs, count:(s.runs||[]).length,
  body(){ return (s.runs||[]).length ? s.runs.slice(0,14).map(r => `<div class="run">
      <span class="tag ${esc(r.status)}">${esc(r.status||"·")}</span>
      <span class="who">${esc((r.agent||"").replace("dm-",""))}</span>
      <span class="what">${r.slice?`<a data-slice="${esc(r.slice)}" title="the whole story of this slice">${esc(r.slice)}</a>`:""}${r.note?" — "+esc(r.note):""}</span>
      <span class="when">${rel(r.ts)}</span></div>`).join("")
    : `<div class="empty">No agent has run yet — give the machine an intent with <span class="cmd">/dm</span></div>`; } });
