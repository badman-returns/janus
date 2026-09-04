// Every panel, in the order the sidebar groups them. A panel is a pure function of the
// /api/state payload returning {name, icon, count?, alert?, nopad?, body()}; it never
// touches the DOM — grid.js owns rendering and wires the data-attributes it emits.
import gates from "./gates.js";
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
  return { gates: gates(s), ...terminals(s), proof: proof(s), runs: runs(s),
           activity: activity(s), agents: agents(s), board: board(s), git: git(s),
           decisions: decisions(s), handoff: handoff(s) };
}
