// One tile per tmux window. A live ttyd iframe when ttyd is installed, a polled
// capture-pane snapshot when it is not. Returns a map, not one def: the windows are data.
import { esc } from "../util.js";
import { ICON } from "../icons.js";
import { termURL } from "../theme.js";

export default s => Object.fromEntries((s.tmux||[]).map(w => ["term:"+w.window, {
  name:"terminal · "+w.window, icon:ICON.term, nopad:true,
  body(){ return s.ttyd_port
    ? `<iframe class="termf" data-termf="${esc(w.window)}" src="${termURL(w.window, s.ttyd_port)}" title="terminal ${esc(w.window)}" allow="clipboard-read; clipboard-write"></iframe>`
    : `<div class="term" data-term="${esc(w.window)}"><div class="ln">loading…</div></div>
       <div class="termnote">read-only snapshot — <span class="cmd">brew install ttyd</span>, then restart the machine, for a live terminal</div>`; } }]));
