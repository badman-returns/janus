// What the architect wrote: .planning/specs and .planning/notes.
import { esc } from "../util.js";
import { ICON } from "../icons.js";

export default s => ({ name:"Board", icon:ICON.board, count:(s.specs||[]).length+(s.notes||[]).length||null,
  body(){ const rows = [...(s.specs||[]).map(f=>[f.name,f.mtime,""]), ...(s.notes||[]).map(f=>[f.name,f.mtime,"note"])];
    return rows.length ? rows.map(([n,t,k]) => `<div class="rowi"><span>${k?"▫ ":""}${esc(n)}</span><span class="when">${esc(t)}</span></div>`).join("")
    : `<div class="empty">No specs yet — the architect writes to <span class="cmd">.planning/specs/</span></div>`; } });
