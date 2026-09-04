# Operator's guide

How to run Janus day to day. Two ways to use it: **architecture only** (agents, gates,
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
claude plugin install janus@janus-marketplace       # architecture
claude plugin install mission-control@janus-marketplace        # cockpit (skip on an account that only wants the architecture)
brew install ttyd                                           # cockpit only; without it tiles are read-only snapshots
bash ~/Documents/rootman/delivery-machine/plugin/scripts/install-login.sh   # optional: machines come up at login
alias janus='bash ~/Documents/rootman/delivery-machine/plugin/scripts/janus.sh'   # the front door, from anywhere
alias mission='bash ~/Documents/rootman/delivery-machine/plugin/scripts/dm.sh'     # this project's machine
```
Each Claude account is its own install (`CLAUDE_CONFIG_DIR=~/.claude-x claude plugin …`).
On macOS, launchd cannot read `~/Documents` without Full Disk Access for `/bin/bash` — grant it once.

## Once per project

```bash
cd <project> && claude      # on the account this project uses
> /dm-init
```
Detects services, writes `.delivery/config.json`, scaffolds `.delivery/ .planning/ proof/`, appends a
"Janus" section to `CLAUDE.md`, drops a `dm-proof` GitHub Actions workflow if there is a
remote, starts the machine. Then edit `config.json` by hand for: `claude_config_dir` (the account),
`ntfy_topic` (phone pushes — subscribe to the same topic in the ntfy app), `proof_dir` (if proof does
not live at the machine root), and the `services` map whenever a new service appears.

## Every session — start

Three doors into the same room; pick whichever is nearest.

**From anywhere — you don't remember which project, or don't want to `cd`:**

```bash
janus                       # every machine on this host, pick one, land in it
janus iit-roorkee           # skip the picker when you already know
```

The picker lists each machine with what it is waiting on and the last line of its ledger, so
you can see where a machine stopped before you enter it. `↑↓` to move, `⏎` or a number to open,
`d` for that machine's dashboard, `q` to leave. Opening does exactly what `mission` does below.

**From inside a project:**

```bash
cd <project>
mission                     # = dm.sh: machine up, a Claude opened INSIDE it, your terminal attached
mission --resume <id>       # same, resuming a session
> /dm                       # the constitution loads; it checks the inbox first
> <your intent, in plain words>
```
**From the browser:** open `http://localhost:<port>` (the fleet page lists every machine), press
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
- **Stop the whole machine**: `bash <plugin>/scripts/dm-stop.sh` — writes the handoff, stops the
  services, kills the session, and marks the registry stopped. `--pause` keeps the session and the
  ledger and only takes the services down. `dm.sh` brings it back. Files are untouched.
  A bare `tmux kill-session -t dm-<project>` also works but leaves **no handoff**, leaves the
  registry claiming the machine is running, and — the one that actually costs you a morning —
  can **orphan the services**, which keep their ports. The next `orchestrator.sh` then starts a
  dev server that dies on `EADDRINUSE`, its window scrolls the failure away, and the port still
  answers `200` from the orphan, so everything looks fine. `dm-stop.sh` sends `C-c` to each
  service window before killing the session, which is the whole reason it does them in that order.
  If a service will not bind: `lsof -nP -iTCP:<port> -sTCP:LISTEN` and check the start time.
- **Stop every machine**: `tmux kill-server` — same caveat, no handoffs. `dm-boot.sh` restores the
  ones not marked stopped.

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
- Handoffs are automatic (PreCompact **and** Stop → `HANDOFF.md`, SessionStart injects it). Rotate at seams.
- Every intent declares a checklist before the first edit (`checklist.sh`), and each item names what
  will prove it — the script refuses one that does not.
- `gate-check.sh` stops a write once the slice passes `gate.max_files` or touches a `gate.guarded`
  path without an approved checklist, and it re-checks on **every** write, so a task that grows
  mid-flight stops when it grows rather than when it started. It fails open: a broken gate must
  never block all editing. **Opt-in** — no `gate` key in `config.json` and it does nothing, so
  upgrading the plugin never starts refusing edits in a project that did not ask for it.
- The verifier's reject loop is bounded at two rounds; a third failure goes to the operator at
  Gate 2 instead of back to the builder.
- Edits under `knowledge_paths` are logged to `knowledge.log`, including absolute paths outside
  the repo — which is the only trace a write to a memory directory leaves at all.

## What the cockpit shows beyond terminals and cards

- **Usage** — the header pill and the session's sidebar badge read Claude Code's own status line
  (`ctx 11% · 5h 40% · $11.88`); the 5-hour figure turns amber at 80 % and red at 95 %, which is when a
  run will pause.
- **Slice story** — click any slice name in *Agent runs*: spec → ledger timeline → review findings →
  commits → proof thumbnails → decisions, one page. `GET /api/slice?name=<slice>` for the same as JSON.
- **Gate threads** — a rejection with a note and the revised gate that follows stay together
  (`.delivery/threads/<gate>.md`); the card shows "round N · previous rounds".
- **Housekeeping the machine does** — every `orchestrator.sh` run prunes merged, clean worktrees
  (`dm-prune.sh`, branches kept); services and `dm-run.sh` commands receive keychain secrets declared in
  `config.json` `secrets` (`secrets-env.sh`); the foundry drafts a skill candidate when the same agent
  fails the same slice three times or the same note prefix repeats.

## Where things live

`plugin/` the architecture (agents, skills, hooks, scripts, tests) · `plugin-mc/` the cockpit ·
`PROTOCOL.md` the seam · `docs/superpowers/` design + plan · `proof/cockpit/` evidence for the
cockpit itself · `~/.delivery-machine/registry.json` the fleet · per project `.delivery/ .planning/ proof/`.
