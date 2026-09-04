// The fleet page: every Janus machine on this host, from /api/fleet, every 5s.
const esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
try{ if(localStorage.getItem("dm2-theme")==="light") document.documentElement.setAttribute("data-theme","light"); }catch{}
async function load(){
  let rows=[];
  try{ rows=await (await fetch("/api/fleet")).json(); }catch{}
  document.getElementById("ts").textContent=new Date().toLocaleTimeString();
  const g=document.getElementById("grid");
  if(!rows.length){ g.innerHTML=`<div class="empty" style="grid-column:1/-1">No machines yet. Run <b>orchestrator.sh</b> in a project to add one.</div>`; return; }
  g.innerHTML=rows.map(r=>`<a class="card ${r.waiting?"needs":""}" href="http://localhost:${r.port}">
    <div class="cn"><span class="sd ${r.alive?"up":""}"></span><b>${esc(r.project)}</b>
      ${r.waiting?`<span class="pill acc">${r.waiting} waiting</span>`:`<span class="pill">${r.alive?"running":"stopped"}</span>`}</div>
    <div class="meta">
      <div class="r"><span>dashboard</span><span>:${r.port}</span></div>
      <div class="r"><span>terminal</span><span>${r.ttyd_port?":"+r.ttyd_port:"—"}</span></div>
      <div class="r"><span>since</span><span>${esc(r.started||"—")}</span></div>
    </div></a>`).join("");
}
load(); setInterval(load,5000);
