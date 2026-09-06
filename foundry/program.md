# foundry — what to improve tonight, and how to know it improved

You are improving Janus, the plugin in `plugin/`. One change per round. Evidence first.

## Where this runs
The loop is started in the main checkout, `~/code/janus`, and builds from
its default branch — read from the refs, so whatever the operator has checked out or half-edited
there is irrelevant. It never switches that checkout, never checks anything out in it, never
stashes: each round gets its own throwaway worktree at `~/.brain/foundry/wt` (`FOUNDRY_WT` moves
it), removed when the round ends. The only thing the loop writes in the operator's tree is the
line it appends to `foundry/log.md`, which is gitignored.

Started from a linked worktree it refuses and says so — those are build checkouts parked on
somebody's branch (`FOUNDRY_ALLOW_WORKTREE=1` if you ever mean it).

You are reading this file from the round's worktree, so it is the copy on the default branch.
This file reaches `master` only when the branch carrying it merges; until then the night job finds
nothing to read and stops with one log line, `no foundry/program.md on <branch>`.

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
Six rounds, or 06:30 (`--until`, which the night job passes and a by-hand run normally leaves off),
or a red baseline — the eval is run once on an untouched worktree of the default branch before
round 1, and if that is already red the night stops rather than blame six rounds for it. Nothing
merges. The operator approves kept branches from the morning brief, one tap each.
