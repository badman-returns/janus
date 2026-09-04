// Every panel, in the order the sidebar groups them. A panel is a pure function of the
// /api/state payload returning {name, icon, count?, alert?, nopad?, body()}; it never
// touches the DOM — grid.js owns rendering and wires the data-attributes it emits.
import gates from "./gates.js";
import inflight from "./inflight.js";
import knowledge from "./knowledge.js";
import checklist from "./checklist.js";
import terminals from "./terminals.js";
import proof from "./proof.js";
import runs from "./runs.js";
import activity from "./activity.js";
import agents from "./agents.js";
import board from "./board.js";
import git from "./git.js";
import decisions from "./decisions.js";
import handoff from "./handoff.js";

export function tileDefs(s){
  // insertion order is the band order the sidebar and the default layout follow:
  // waiting on you → in flight → terminals → proven (runs + proof) → knowledge
  return { gates: gates(s), inflight: inflight(s), ...terminals(s), runs: runs(s), proof: proof(s),
           knowledge: knowledge(s), checklist: checklist(s), activity: activity(s), agents: agents(s),
           board: board(s), git: git(s), decisions: decisions(s), handoff: handoff(s) };
}
