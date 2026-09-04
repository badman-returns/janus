// The one mutable thing the modules share, plus the two calls that point back up the graph.
// A registry, not a framework: boot.js fills in rebuild/refresh once, so grid, sidebar,
// drawer and palette can trigger a redraw without importing each other in a cycle.
export const app = {
  S: null,            // the last /api/state payload
  project: null,      // its project name — the localStorage key is scoped to it
  layout: null,       // {open:[], order:[], sizes:{}, focus:[], side:bool, seenTerm:bool}
  rebuild(){},        // re-render tiles + sidebar from app.S
  refresh(){},        // refetch /api/state and render
};

// per-project panel layout, in localStorage. Same key as before: "dm2-<project>".
export const store = {
  get k(){ return "dm2-" + (app.project||"x"); },
  load(){ try{ return JSON.parse(localStorage.getItem(this.k))||null }catch{ return null } },
  save(v){ try{ localStorage.setItem(this.k, JSON.stringify(v)) }catch{} },
};

export const DEFAULT_OPEN = ["gates","agents","proof","runs"];

// inbox items waiting on the operator vs the operator's own writing — the same split the
// server makes in waitingIn(); the page needs both halves.
export const asks = s => (s.inbox||[]).filter(i => !/^(reply|note)-/.test(i.name));
export const outbound = s => (s.inbox||[]).filter(i => /^(reply|note)-/.test(i.name));

// every POST is followed by a refetch, so the page never guesses what the write did
export async function post(url, payload){
  try { await fetch(url, { method:"POST", headers:{"content-type":"application/json"}, body:JSON.stringify(payload) }); }
  finally { app.refresh(); }
}

// Reconcile the remembered layout with the panels that exist right now: drop keys whose
// panel is gone, add newly-pinned ones, and open the first terminal the operator ever sees.
export function ensureLayout(defs){
  const l = app.layout || (app.layout = store.load() || { open:[...DEFAULT_OPEN], sizes:{}, order:[] });
  const terms = Object.keys(defs).filter(k=>k.startsWith("term:"));
  if (!l.seenTerm && terms.length){ l.open.splice(1,0,terms[0]); l.seenTerm = true; store.save(l); }
  l.open = l.open.filter(k => defs[k]);
  const order = l.order.filter(k => l.open.includes(k));
  l.open.forEach(k => { if(!order.includes(k)) order.push(k); });
  l.order = order;
  l.focus = (l.focus||[]).filter(k => defs[k]);   // 0–2 keys: focus / split
}

// nav semantics: show k. shift adds it as the second pane; showing an already-shown pane is a no-op
export function toggleFocus(k, add){
  const l = app.layout, f = l.focus;
  if (add && f.length === 1 && f[0] !== k) l.focus = [f[0], k];
  else if (!(f.length === 1 && f[0] === k)) l.focus = [k];
  if (!l.open.includes(k)){ l.open.push(k); l.order.push(k); }
  store.save(l); app.rebuild();
}
