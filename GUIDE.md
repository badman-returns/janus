# Operator's guide

How to run the delivery machine day to day. Two ways to use it: **architecture only** (agents, gates,
ledger, tmux — gates arrive as terminal prompts) or **with the cockpit** (the same, plus every terminal,
gate and question in a browser tab and on your phone). The file contract between the two is
`PROTOCOL.md`; nothing else couples them.

## What is running, in one picture

```
you ──(browser / phone / terminal tile)──► inbox files ──► Claude session inside tmux ──► agents
                                                                    │
     cockpit (optional) ◄── reads .delivery/ .planning/ proof/ ◄────┘  ledger, heartbeats, proof
```

Per project there is one tmux session `dm-<project>`. Each window is one thing that runs: your
services, the Claude session(s), and — with the cockpit — `mission` (dashboard), `ttyd` (web terminal),
`watch` (pickup). Everything the machine knows is a file under `.delivery/`, `.planning/`, `proof/`.

## Once per Mac / account

```bash
claude plugin marketplace add ~/Documents/rootman/delivery-machine
claude plugin install delivery-machine@dm-marketplace       # architecture
claude plugin install mission-control@dm-marketplace        # cockpit (skip on an account that only wants the architecture)
brew install ttyd                                           # cockpit only; without it tiles are read-only snapshots
bash ~/Documents/rootman/delivery-machine/plugin/scripts/install-login.sh   # optional: machines come up at login
alias mission='bash ~/Documents/rootman/delivery-machine/plugin/scripts/dm.sh'
```
Each Claude account is its own install (`CLAUDE_CONFIG_DIR=~/.claude-x claude plugin …`).
On macOS, launchd cannot read `~/Documents` without Full Disk Access for `/bin/bash` — grant it once.

## Once per project

```bash
cd <project> && claude      # on the account this project uses
> /dm-init
```
Detects services, writes `.delivery/config.json`, scaffolds `.delivery/ .planning/ proof/`, appends a
"Delivery machine" section to `CLAUDE.md`, drops a `dm-proof` GitHub Actions workflow if there is a
remote, starts the machine. Then edit `config.json` by hand for: `claude_config_dir` (the account),
`ntfy_topic` (phone pushes — subscribe to the same topic in the ntfy app), `proof_dir` (if proof does
not live at the machine root), and the `services` map whenever a new service appears.

## Every session — start

```bash
cd <project>
mission                     # = dm.sh: machine up, a Claude opened INSIDE it, your terminal attached
mission --resume <id>       # same, resuming a session
> /dm                       # the constitution loads; it checks the inbox first
> <your intent, in plain words>
```
Or, with the cockpit: open `http://localhost:<port>` (fleet page lists every machine), press
**+ Session**, click into the tile, type `/dm`. From then on the terminal is optional — the tile *is*
the session.

A session started with plain `claude` outside tmux still works; the machine tells it so at start,
it gets no tile, and its gate answers reach it on its next Stop instead of instantly.

## Every session — what you do

1. **Gate 1** — the architect's plan lands as `gate-*.txt`: a card in *Waiting on you*, a push on the
   phone. Read `.planning/specs/<date>-<slice>.md`. Approve, or reject with a note; the architect
   revises. Your reply is typed into the session by the watcher.
2. **Questions and permissions** — any `AskUserQuestion` or permission prompt in the session becomes
   a card with its options. Answer there or in the terminal; either works. Unanswered for 10 min → the
   terminal prompt appears as normal.
3. **Gate 2** — the verifier's `proof/<slice>/` (screenshots + README) lands as a card. The ledger
   accepted `done` only because that README is newer than the branch's last commit; the gate could
   not have opened otherwise. Approve → you merge: `git merge --ff-only <branch>`. The machine never
   merges and never deploys.
4. **Free text** — the composer at the bottom of the cockpit (or a `note-*` file) is a message to the
   orchestrator. Its answers come back as green "machine replied" cards.

## Every session — stop

- **Pause the session**: close the tab or detach (`Ctrl-b d`). The session keeps running in tmux; the
  ledger, branch and inbox are on disk. A usage cap does the same thing to you: nothing is lost.
- **End the session**: `Ctrl-C` twice in its tile/window, or `/exit`. The `claude` window closes; the
  services stay up.
- **Stop a service**: the ▮ button on its tile (Ctrl-C into that window), ↻ restarts it.
- **Stop the whole machine**: `tmux kill-session -t dm-<project>` — services, cockpit, watcher, all of
  it. `orchestrator.sh` (or `mission`) brings it back identically. Files are untouched.
- **Stop every machine**: `tmux kill-server`. `dm-boot.sh` restores them all.

## Reading the state without the cockpit

| question | where |
|---|---|
| what is waiting on me | `ls .delivery/inbox/` — `gate-*`, `ask-*` |
| what happened | `tail .delivery/runs.jsonl` — only `dm-verifier … done` means verified |
| what was decided | `.delivery/decisions.md` |
| what is the plan | `.planning/specs/` |
| is it done | `proof/<slice>/README.md` exists and `bash …/scripts/proof-fresh.sh <slice>` prints the branch |
| who is alive | `.delivery/agents/*.json` (heartbeats); `bash …/scripts/is-live.sh; echo $?` |
| logs of anything | `tmux capture-pane -p -t dm-<project>:<window>` |

Answer a gate by hand: `printf 'RE: gate-x.txt\nAPPROVE\n' > .delivery/inbox/reply-$(date +%s)-gate-x-txt.txt`
(then delete the gate file — the cockpit does both in one click).

## The rules the machine enforces on itself

- Nothing long-lived runs in an agent's background: `dm-run.sh <window> <cmd>` or it does not run.
- `runs.jsonl` is written only by `run-log.sh`; `done` only by the verifier, only with fresh proof.
- Gate 2 is written only by `dm-gate.sh`, which refuses stale or missing proof.
- Branches are handed over un-merged. Worktrees per builder.
- Handoffs are automatic (PreCompact → `HANDOFF.md`, SessionStart injects it). Rotate at seams.

## Where things live

`plugin/` the architecture (agents, skills, hooks, scripts, tests) · `plugin-mc/` the cockpit ·
`PROTOCOL.md` the seam · `docs/superpowers/` design + plan · `proof/cockpit/` evidence for the
cockpit itself · `~/.delivery-machine/registry.json` the fleet · per project `.delivery/ .planning/ proof/`.
