// Branches awaiting merge, then where HEAD is — a slice's branch IS the review unit.
import { esc } from "../util.js";
import { ICON } from "../icons.js";

export default s => ({ name:"Branches", icon:ICON.git,
  body(){ return (s.git.branches ? `<pre class="mono">${esc(s.git.branches)}</pre>` : `<div style="color:var(--mut);font-size:12.5px;margin-bottom:8px">Nothing awaiting merge.</div>`) +
    `<pre class="mono" style="color:var(--mut)">on ${esc(s.git.branch)||"—"} · ${esc(s.git.status)||"clean"}\n${esc(s.git.log)}</pre>`; } });
