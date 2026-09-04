// The four things every module needs. No state, no DOM ownership.
export const $ = id => document.getElementById(id);
export const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
export const rel = iso => { if(!iso) return ""; const m=(Date.now()-new Date(iso))/60000;
  return m<1?"now":m<60?Math.round(m)+"m":m<1440?Math.round(m/60)+"h":Math.round(m/1440)+"d"; };
// a tile key ("term:claude-2") is not a valid element id fragment
export const cssId = k => k.replace(/[^a-z0-9]/gi,"_");
