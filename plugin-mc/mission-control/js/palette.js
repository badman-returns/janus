// ⌘K: every panel, every focus target, the standing actions, and one Approve per open gate.
import { $, esc, cssId } from "./util.js";
import { ICON } from "./icons.js";
import { app, store, post, asks, toggleFocus } from "./state.js";
import { tileDefs } from "./panels/index.js";
import { toggleDrawer } from "./drawer.js";

function cmdActions(){
  const layout = app.layout;
  const defs = app.S ? tileDefs(app.S) : {};
  const acts = [];
  Object.entries(defs).forEach(([k,t]) => {
    const open = layout && layout.open.includes(k);
    acts.push({ label:(open?"Show":"Open")+" "+t.name, grp:"tile", icon:t.icon, run(){
      if (!open){ layout.open.push(k); layout.order.push(k); store.save(layout); app.rebuild(); }
      const el = $("b-"+cssId(k)); if (el) el.closest(".tile").scrollIntoView({behavior:"smooth",block:"center"});
    }});
    acts.push({ label:"Focus "+t.name, grp:"focus", icon:t.icon, run(){ toggleFocus(k); } });
  });
  acts.push({ label:"Overview", grp:"focus", icon:ICON.board, run(){ layout.focus=[]; store.save(layout); app.rebuild(); } });
  acts.push({ label:(layout && layout.side ? "Unpin" : "Pin")+" sidebar", grp:"action", icon:ICON.right, run(){ layout.side = !layout.side; store.save(layout); app.rebuild(); } });
  acts.push({ label:"Open stream", grp:"action", icon:ICON.reply, run:()=>toggleDrawer(true) });
  acts.push({ label:"Cycle theme (auto / light / dark)", grp:"action", icon:ICON.doc, run:()=>$("themeBtn").click() });
  acts.push({ label:"Open fleet", grp:"action", icon:ICON.board, run:()=>location.href="/fleet" });
  acts.push({ label:"New Claude session", grp:"action", icon:ICON.term, run:()=>$("newSess").click() });
  asks(app.S||{inbox:[]}).forEach(i => acts.push({ label:"Approve "+i.name, grp:"gate", icon:ICON.gate, run(){
    post("/api/inbox", { kind:"reply", re:i.name, text:"APPROVE" }); }}));
  return acts;
}
let cmdSel = 0, cmdFiltered = [];
function drawCmd(q){
  const acts = cmdActions();
  cmdFiltered = q ? acts.filter(a => a.label.toLowerCase().includes(q.toLowerCase())) : acts;
  cmdSel = Math.min(cmdSel, Math.max(0, cmdFiltered.length-1));
  $("cmdList").innerHTML = cmdFiltered.map((a,i) => `<div class="cmdrow ${i===cmdSel?"sel":""}" data-i="${i}">
    ${a.icon}<span>${esc(a.label)}</span><span class="grp">${a.grp}</span></div>`).join("")
    || `<div style="padding:14px;color:var(--mut);font-size:13px">No match.</div>`;
  $("cmdList").querySelectorAll("[data-i]").forEach(r => r.onclick = () => runCmd(+r.dataset.i));
}
function openCmd(){ $("cmdk").classList.add("open"); cmdSel=0; $("cmdInput").value=""; drawCmd(""); $("cmdInput").focus(); }
function closeCmd(){ $("cmdk").classList.remove("open"); }
function runCmd(i){ const a = cmdFiltered[i]; if(!a) return; closeCmd(); a.run(); }
$("cmdInput").addEventListener("input", e => { cmdSel=0; drawCmd(e.target.value); });
$("cmdInput").addEventListener("keydown", e => {
  if (e.key==="ArrowDown"){ e.preventDefault(); cmdSel=Math.min(cmdSel+1,cmdFiltered.length-1); drawCmd($("cmdInput").value); }
  else if (e.key==="ArrowUp"){ e.preventDefault(); cmdSel=Math.max(cmdSel-1,0); drawCmd($("cmdInput").value); }
  else if (e.key==="Enter"){ e.preventDefault(); runCmd(cmdSel); }
  else if (e.key==="Escape"){ closeCmd(); }
});
$("cmdk").addEventListener("click", e => { if (e.target.id==="cmdk") closeCmd(); });
addEventListener("keydown", e => {
  if ((e.metaKey||e.ctrlKey) && e.key.toLowerCase()==="k"){ e.preventDefault();
    $("cmdk").classList.contains("open") ? closeCmd() : openCmd(); }
});
