// Heartbeats: who is live, idle or gone. A row opens that agent's full history in the drawer.
import { esc, rel } from "../util.js";
import { ICON } from "../icons.js";

export default s => ({ name:"Agents & sessions", icon:ICON.runs,
  count:(s.agents||[]).filter(a=>a.alive).length||null,
  alert:(s.agents||[]).some(a=>a.alive),
  body(){ return (s.agents||[]).length ? s.agents.map(a => {
      const st = a.alive?"on":a.idle?"idle":"off";
      return `<div class="agent" data-agent="${esc(a.sid)}" title="click for this agent's full history"><span class="adot ${st}"></span>
        <span class="aid">${esc(a.sid)}</span>
        <span class="arole">${esc(a.role||"session")}</span>
        <span class="adetail">${esc(a.detail||a.event||"")}</span>
        <span class="awhen">${a.alive?"live":rel(a.ts)}</span></div>`; }).join("")
    : `<div class="empty">No live sessions tracked yet — each Claude session in this project appears here once the plugin hooks fire. Parallel builders show as their own rows.</div>`; } });
