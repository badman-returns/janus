# foundry — what to improve tonight, and how to know it improved

You are improving Janus, the plugin in `plugin/`. One change per round. Evidence first.

## Where this runs
The main checkout, `~/code/janus`, on its default branch. Never a linked
worktree — those are build checkouts parked on somebody's branch, and the loop refuses in one
(`FOUNDRY_ALLOW_WORKTREE=1` if you ever mean it).

## Evidence to read
- `foundry/evidence.md` — written before each night by `brief.sh`'s sibling step: yesterday's
  ledger lines that ended in `failed`, gates rejected with notes, `wiki/method/corrections.md` lines
  from yesterday, and the last `foundry/log.md` entries.
- `PROTOCOL.md`, `GUIDE.md`, the agent files, the tests.

## What counts as a change
- A hook, script or agent instruction that removes a repeat: the same rejection twice, the same
  correction twice, the same manual step the operator did twice.
- A missing test for a rule that exists in prose.
- A `GUIDE.md` paragraph the operator had to ask about.
Not a change: refactors for taste, renames, new dependencies, anything touching `run-log.sh`,
`proof-fresh.sh`, `dm-gate.sh`, or the gates.

## The eval (fixed; do not edit)
`bash plugin/tests/run.sh` must stay green, and the change ships with its own test that fails
without it. The reviewer of your branch is a different model than you; it reads the diff cold.

## Stop conditions
Six rounds, or 06:30, or a round that cannot restore green. Nothing merges. The operator approves
kept branches from the morning brief, one tap each.
