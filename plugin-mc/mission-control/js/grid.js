// The Overview grid: tile skeleton, bodies, and every handler the panels' data-attributes ask
// for. Panels emit HTML only; all wiring is here, which is why they need no DOM access.
import { $, esc, cssId } from "./util.js";
import { ICON } from "./icons.js";
import { app, store, post, ensureLayout, toggleFocus } from "./state.js";
import { tileDefs } from "./panels/index.js";
import { drawSide } from "./sidebar.js";
import { focusAgent, focusSlice } from "./drawer.js";

const bodyHash = {};
function drawSkeleton(defs){
  const layout = app.layout;
  // rebuilding the grid destroys every iframe (ttyd reconnects, xterm flashes its size) —
  // only do it when the tile set, order, or sizes actually changed; bodies/alerts/counts refresh in fillBodies
  const sig = JSON.stringify([layout.order, layout.sizes, layout.focus||[]]);
  if (sig === drawSkeleton.sig && $("grid").children.length) return;
  drawSkeleton.sig = sig;
  const keys = layout.focus.length ? layout.focus : layout.order;
  document.body.classList.toggle("focusmode", layout.focus.length > 0);
  document.body.classList.toggle("split", layout.focus.length === 2);
  $("grid").innerHTML = keys.map(k => {
    const t = defs[k]; const size = layout.sizes[k] || (k.startsWith("term:")?"xl":"m");
    return `<div class="tile ${size} ${t.alert?"alert":""} ${layout.focus.includes(k)?"focus":""}" data-k="${esc(k)}" draggable="true">
      <div class="t-h">${t.icon}<span class="name">${esc(t.name)}</span>
        ${t.count!=null?`<span class="cnt">${t.count}</span>`:""}
        <span class="hb">
          ${k.startsWith("term:") && !/^term:claude/.test(k)?`
            <button class="svcbtn" data-svc="restart" data-w="${esc(k.slice(5))}" data-tip="Restart this service" aria-label="Restart">${ICON.restart}</button>
            <button class="svcbtn stop" data-svc="stop" data-w="${esc(k.slice(5))}" data-tip="Stop this service (Ctrl-C)" aria-label="Stop">${ICON.stop}</button>`:""}
          <button data-focus="${esc(k)}" data-tip="${layout.focus.includes(k)?"Back to overview (Esc)":"Open full width · shift-click to split"}" aria-label="Focus">${layout.focus.includes(k)?ICON.min:ICON.max}</button>
          ${layout.focus.length?"":`<button data-size="${esc(k)}" data-tip="Cycle size" aria-label="Resize">${ICON.size}</button>`}
          <button data-close="${esc(k)}" data-tip="Remove from overview" aria-label="Close">${ICON.close}</button></span></div>
      <div class="t-b ${t.nopad?"nopad":""}" id="b-${cssId(k)}"></div></div>`;
  }).join("");
  Object.keys(bodyHash).forEach(k=>delete bodyHash[k]);
  wireGrid();
}
function fillBodies(defs){
  app.layout.order.forEach(k => {
    const el = $("b-"+cssId(k)); if (!el) return;
    const html = defs[k].body();
    if (bodyHash[k] !== html){ bodyHash[k] = html; el.innerHTML = html; wireBody(el); }
    // alert ring + count refresh without full rebuild
    const tile = el.closest(".tile");
    tile.classList.toggle("alert", !!defs[k].alert);
    const cnt = tile.querySelector(".cnt"); if (cnt && defs[k].count!=null) cnt.textContent = defs[k].count;
  });
  refreshTerms();
}
function wireGrid(){
  const layout = app.layout;
  // size cycle + close
  $("grid").querySelectorAll("[data-size]").forEach(b => b.onclick = e => { e.stopPropagation();
    const k = b.dataset.size, seq = ["s","m","l","xl"];
    layout.sizes[k] = seq[(seq.indexOf(layout.sizes[k]||"m")+1)%seq.length];
    store.save(layout); app.rebuild(); });
  $("grid").querySelectorAll("[data-close]").forEach(b => b.onclick = e => { e.stopPropagation();
    const k = b.dataset.close;
    layout.open = layout.open.filter(x=>x!==k); layout.order = layout.order.filter(x=>x!==k);
    store.save(layout); app.rebuild(); });
  $("grid").querySelectorAll("[data-focus]").forEach(b => b.onclick = e => { e.stopPropagation();
    const k = b.dataset.focus;
    if (layout.focus.includes(k)){ layout.focus = layout.focus.filter(x=>x!==k); store.save(layout); app.rebuild(); }   // ⤡ leaves this pane
    else toggleFocus(k, e.shiftKey); });
  $("grid").querySelectorAll("[data-svc]").forEach(b => b.onclick = async e => { e.stopPropagation();
    const w = b.dataset.w, act = b.dataset.svc; b.disabled = true;
    try { await fetch("/api/service", { method:"POST", headers:{"content-type":"application/json"},
      body: JSON.stringify({ window:w, action:act }) }); } catch {}
    setTimeout(refreshTerms, 700); setTimeout(()=>{b.disabled=false;}, 900); });
  // drag reorder
  let dragK = null;
  $("grid").querySelectorAll(".tile").forEach(tile => {
    tile.addEventListener("dragstart", e => { dragK = tile.dataset.k; tile.classList.add("drag");
      e.dataTransfer.effectAllowed = "move"; });
    tile.addEventListener("dragend", () => { tile.classList.remove("drag");
      $("grid").querySelectorAll(".tile").forEach(t=>t.classList.remove("over")); });
    tile.addEventListener("dragover", e => { e.preventDefault(); if (tile.dataset.k!==dragK) tile.classList.add("over"); });
    tile.addEventListener("dragleave", () => tile.classList.remove("over"));
    tile.addEventListener("drop", e => { e.preventDefault(); tile.classList.remove("over");
      const to = tile.dataset.k; if (!dragK || dragK===to) return;
      const o = layout.order; o.splice(o.indexOf(dragK),1); o.splice(o.indexOf(to),0,dragK);
      store.save(layout); app.rebuild(); });
  });
}
function wireBody(el){
  el.querySelectorAll("[data-agent]").forEach(r => r.onclick = () => focusAgent(r.dataset.agent));
  el.querySelectorAll("[data-slice]").forEach(a => a.onclick = () => focusSlice(a.dataset.slice));
  el.querySelectorAll("[data-act]").forEach(b => b.onclick = async () => {
    const re = b.dataset.re, note = el.querySelector(`[data-note-for="${CSS.escape(re)}"]`)?.value || "";
    b.disabled = true;
    await post("/api/inbox", { kind:"reply", re, text: b.dataset.act.toUpperCase()+(note?": "+note:"") });
  });
  el.querySelectorAll("[data-dismiss]").forEach(b => b.onclick = async () => {
    b.disabled = true; await post("/api/replies/dismiss", { name: b.dataset.dismiss });
  });
  // answer a question/permission card: picked options + free text → reply-*.txt, which ask.sh is polling for
  el.querySelectorAll("[data-ask-send]").forEach(b => b.onclick = async () => {
    const name = b.dataset.askSend, card = el.querySelector(`[data-ask="${CSS.escape(name)}"]`);
    const picked = [...card.querySelectorAll("input:checked")].map(i => i.value);
    const typed = card.querySelector("[data-ask-text]").value.trim();
    const text = [...picked, typed].filter(Boolean).join(", "); if (!text) return;
    b.disabled = true; await post("/api/inbox", { kind:"reply", re:name, text });
  });
}

// terminals without ttyd: poll capture-pane and keep the view pinned to the bottom
const openLogAtBottom = {};
export async function refreshTerms(){
  for (const t of document.querySelectorAll("[data-term]")) {
    const w = t.dataset.term;
    try {
      const txt = await (await fetch("/api/logs?w="+encodeURIComponent(w))).text();
      const atBottom = t.scrollHeight - t.scrollTop - t.clientHeight < 40;
      const html = txt.split("\n").map(l =>
        `<div class="ln ${/(200|201|✓|listening)/.test(l)?"ok":""}">${esc(l)}</div>`).join("");
      if (t.dataset.h !== String(html.length)) { t.dataset.h = String(html.length); t.innerHTML = html; }
      if (atBottom || !openLogAtBottom[w]) { t.scrollTop = t.scrollHeight; openLogAtBottom[w] = true; }
    } catch {}
  }
}
setInterval(refreshTerms, 2600);

export function rebuild(){ if (!app.S) return; const defs = tileDefs(app.S);
  ensureLayout(defs); drawSkeleton(defs); fillBodies(defs); drawSide(defs); }
