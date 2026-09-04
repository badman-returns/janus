// The proof gallery: one row per slice, its screenshots served from /proof/.
import { esc } from "../util.js";
import { ICON } from "../icons.js";

export default s => ({ name:"Proof", icon:ICON.proof, count:(s.proof||[]).length,
  body(){ return (s.proof||[]).length ? s.proof.map(p => `<div class="slice">
      <div class="sh"><b>${esc(p.slice)}</b><span class="when">${esc(p.mtime)}</span></div>
      <div class="shots">${p.files.filter(f=>/\.(png|jpe?g|gif)$/i.test(f.name)).map(f =>
        `<a href="/proof/${encodeURIComponent(p.slice)}/${encodeURIComponent(f.name)}" target="_blank" rel="noopener">
           <img loading="lazy" src="/proof/${encodeURIComponent(p.slice)}/${encodeURIComponent(f.name)}" alt="${esc(f.name)}"></a>`).join("")
        || '<span style="color:var(--mut2);font-size:12px">no images</span>'}</div></div>`).join("")
    : `<div class="empty">No proof yet — and no proof means nothing is done.</div>`; } });
