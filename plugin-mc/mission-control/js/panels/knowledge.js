// KNOWLEDGE — .delivery/knowledge.log, grouped by path, newest first. The rows that matter
// most are the ones marked "outside repo": a write above the project root (a Claude config
// dir's memory/, say) is in no commit and no diff, so this log is the only trace it left at
// all — which is the reason the log exists. The git summary covers only the repo-local half,
// because that is the half git can speak about.
import { esc, rel } from "../util.js";
import { ICON } from "../icons.js";

export default s => {
  const k = s.knowledge || { paths: [], writes: 0, diffstat: "" };
  const out = (k.paths || []).filter(p => p.outside).length;
  return { name: "Knowledge", icon: ICON.doc, size: "l", count: (k.paths || []).length || null,
    body() {
      if (!(k.paths || []).length)
        return `<div class="empty">No knowledge writes logged. Edits under <span class="cmd">knowledge_paths</span>
          (<span class="cmd">config.json</span>) are appended to <span class="cmd">.delivery/knowledge.log</span> by a
          PostToolUse hook — including absolute paths outside this repo, which leave no other trace.</div>`;
      return `<div class="kh">${k.writes} write${k.writes === 1 ? "" : "s"} · ${k.paths.length} path${k.paths.length === 1 ? "" : "s"}${
          out ? ` · <b class="out">${out} outside the repo</b>` : ""}</div>` +
        k.paths.map(p => {
          const cut = p.path.lastIndexOf("/");
          return `<div class="kw">
            <span class="kp" title="${esc(p.path)}">${cut > -1 ? `<i>${esc(p.path.slice(0, cut + 1))}</i>` : ""}<b>${esc(p.path.slice(cut + 1))}</b></span>
            ${p.outside ? `<span class="pill out" title="Outside the project root — no commit, no diff, this log is its only trace">outside repo</span>` : ""}
            <span class="pill">${esc((p.kinds || []).join("/") || "write")}</span>
            <span class="pill" title="Writes logged to this path">×${p.count}</span>
            <span class="when">${esc(rel(p.last))}</span></div>`;
        }).join("") +
        (k.diffstat ? `<div class="kh" style="margin-top:10px">uncommitted, repo-local paths only</div>
           <pre class="mono">${esc(k.diffstat)}</pre>` : "");
    } };
};
