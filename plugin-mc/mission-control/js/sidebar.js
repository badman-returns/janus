// The 56px icon rail: Overview · Sessions · Services · Machine · System. Click opens a panel
// (focus), shift-click splits, the ⊞/⊟ pin adds or removes it from the Overview grid.
import { $, esc } from "./util.js";
import { ICON } from "./icons.js";
import { app, store, toggleFocus } from "./state.js";

export function drawSide(defs){
  const layout = app.layout, S = app.S;
  $("side").classList.toggle("pin", !!layout.side);
  const isTerm = k => k.startsWith("term:"), win = k => k.slice(5);
  const sys = new Set(["control","mission","ttyd","watch"]);
  const keys = Object.keys(defs);
  const sessions = keys.filter(k => /^term:claude/.test(k));
  const services = keys.filter(k => isTerm(k) && !/^term:claude/.test(k) && !sys.has(win(k)));
  const system   = keys.filter(k => isTerm(k) && sys.has(win(k)));
  const panels   = keys.filter(k => !isTerm(k));
  const cmdOf = w => ((S.tmux||[]).find(x => x.window===w) || {}).cmd || "";
  const dot = k => `<span class="dot ${/^(zsh|bash|sh|fish)$/.test(cmdOf(win(k)))?"off":""}" title="${esc(cmdOf(win(k))||"idle shell")}"></span>`;
  const hr5 = w => { const u = (S.usage||[]).find(x => x.window===w); return u && u.hr5!=null ? u.hr5+"%" : null; };
  const item = (k, label, extra="", cnt) => { const t = defs[k], pinned = layout.open.includes(k), c = cnt ?? t.count;
    return `<div class="sd-i ${layout.focus.includes(k)?"on":""} ${t.alert?"alert":""}" data-nav="${esc(k)}" role="button" tabindex="0" title="${esc(label)} — open · shift-click to split">
      ${t.icon}${extra}<span class="lb">${esc(label)}</span>${c!=null?`<i>${esc(c)}</i>`:""}
      <button class="pinb ${pinned?"on":""}" data-pin="${esc(k)}" data-tip="${pinned?"Remove from Overview":"Show in Overview"}" aria-label="Pin to overview">${pinned?ICON.close:ICON.plus}</button></div>`; };
  const nav = (id, label, icon, title) => `<div class="sd-i ${id==="__overview"&&!layout.focus.length?"on":""}" data-nav="${id}" role="button" tabindex="0" title="${esc(title)}">${icon}<span class="lb">${esc(label)}</span></div>`;
  let h = nav("__overview", "Overview", ICON.board, "Overview — every panel you pinned (esc)");
  h += `<div class="sd-g">Sessions</div>` + sessions.map(k => item(k, win(k), dot(k), hr5(win(k)))).join("")
     + nav("__new", "New session", ICON.plus, "Start a Claude session inside the machine");
  h += `<div class="sd-g">Services</div>` + (services.map(k => item(k, win(k), dot(k))).join("") || `<div class="sd-g" style="padding-top:2px">none</div>`);
  h += `<div class="sd-g">Machine</div>` + panels.map(k => item(k, defs[k].name)).join("");
  h += `<div class="sd-g">System</div>` + system.map(k => item(k, win(k), dot(k))).join("");
  h += `<div class="sd-foot">` + nav("__pin", layout.side ? "Unpin sidebar" : "Keep sidebar open", layout.side ? ICON.left : ICON.right, "Pin the sidebar open (it expands on hover otherwise)") + `</div>`;
  if (drawSide.h === h) return; drawSide.h = h;   // no churn under the pointer on every tick
  $("sideInner").innerHTML = h;
  const go = (el, e) => {
    if (e.target.closest("[data-pin]")) return;
    const k = el.dataset.nav;
    if (k === "__overview"){ layout.focus = []; store.save(layout); app.rebuild(); return; }
    if (k === "__new") return $("newSess").click();
    if (k === "__pin"){ layout.side = !layout.side; store.save(layout); app.rebuild(); return; }
    toggleFocus(k, e.shiftKey);
  };
  $("sideInner").querySelectorAll("[data-nav]").forEach(el => { el.onclick = e => go(el, e);
    el.onkeydown = e => { if (e.key==="Enter" || e.key===" "){ e.preventDefault(); go(el, e); } }; });
  $("sideInner").querySelectorAll("[data-pin]").forEach(b => b.onclick = e => { e.stopPropagation();
    const k = b.dataset.pin;
    layout.open.includes(k) ? (layout.open = layout.open.filter(x=>x!==k), layout.order = layout.order.filter(x=>x!==k))
                            : (layout.open.push(k), layout.order.push(k));
    store.save(layout); app.rebuild(); });
}
