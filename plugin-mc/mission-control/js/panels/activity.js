// Hook events from every Claude session in the project, newest first.
import { esc, rel } from "../util.js";
import { ICON } from "../icons.js";

export default s => ({ name:"Session activity", icon:ICON.activity, count:(s.activity||[]).length||null,
  body(){ return (s.activity||[]).length ? s.activity.map(a => `<div class="act">
      <span class="tag ${a.event==="tool"?"done":a.event==="prompt"?"working":""}">${esc(a.event)}</span>
      <span class="what">${esc(a.detail||"")}</span><span class="when">${rel(a.ts)}</span></div>`).join("")
    : `<div class="empty">Lights up once the plugin hooks are installed:<br><span class="cmd">claude plugin install janus@janus-marketplace</span></div>`; } });
