// .delivery/decisions.md, verbatim.
import { esc } from "../util.js";
import { ICON } from "../icons.js";

export default s => ({ name:"Decisions", icon:ICON.doc,
  body(){ return s.decisions ? `<pre class="mono">${esc(s.decisions)}</pre>` : `<div class="empty">None recorded yet.</div>`; } });
