// .delivery/HANDOFF.md — written by the PreCompact hook, read by the next session.
import { esc } from "../util.js";
import { ICON } from "../icons.js";

export default s => ({ name:"Last handoff", icon:ICON.hand,
  body(){ return s.handoff ? `<pre class="mono">${esc(s.handoff)}</pre>` : `<div class="empty">No handoff yet — written automatically before compaction.</div>`; } });
