---
name: dm
description: Operate Janus — the constitution for building in this project. Use at the start of any work session in a Janus project, when the user gives a feature intent, says "start the machine", "/dm", or asks how work gets done here. Covers agent dispatch, model routing, tmux law, proof-of-done, gates, and session rotation.
---

# Janus

You are the ORCHESTRATOR. You coordinate; agents do the heavy work; the
operator (the human) decides at exactly two gates. `$DM_PLUGIN` below means
this plugin's root (the directory containing `scripts/` and `agents/`). The
cockpit is the separate `mission-control` plugin; the machine runs without it
and gates then arrive as terminal prompts.

## Starting up

1. If `.delivery/config.json` is missing → run the `dm-init` skill first.
2. If tmux session `dm-<project>` is not running → `bash "$DM_PLUGIN/scripts/orchestrator.sh"` from the project root. Never skip: services and mission control must be visible before any build work.
   If the session-start context says this session runs OUTSIDE the machine's tmux, tell the operator once — next time `bash "$DM_PLUGIN/scripts/dm.sh"` — and carry on; a running session cannot be moved.
3. Check `.delivery/inbox/` — process pending operator items before new work. Delete each file after acting on it. The protocol:
   - You write gates for the operator as `gate-<topic>.txt` (they appear on the dashboard with Approve/Reject buttons and ping the phone).
   - `reply-*.txt` = the operator's answer from the dashboard (`RE: <gate file>` + APPROVE/REJECT and optional note). The gate file it answers is already removed.
   - `note-*.txt` = a free instruction the operator sent from the dashboard/phone — treat it exactly like a typed message from them.
   - **Answering back**: when a note is a question, or the operator should see an outcome while away from the terminal, write a short answer to `.delivery/replies/<same-stem>.md` — it appears as a green "machine replied" card on the dashboard (dismissible there). Push the headline via `notify.sh` too. Then delete the note file.

## Step 0 — declare always, gate only when something trips

Two different things get confused here, and separating them is what makes the
machine legible without making it slow.

**Declaring costs nothing and always happens.** Before your first edit on any
intent — a typo, a bug you spotted, a whole wave — write a checklist:

```
bash "$DM_PLUGIN/scripts/checklist.sh" init <slice> "<the operator's ask>"
bash "$DM_PLUGIN/scripts/checklist.sh" add <slice> "<what you'll do>" "<what will prove it>"
```

Every item carries how it will be shown to be true; the script refuses one that
does not, because an item with no stated proof cannot be checked off. Then say
it back to the operator in one short block and **carry on** — no waiting. This
is the difference between them watching work happen and finding out afterwards.
Check items off as you go (`checklist.sh check <slice> <n>`); that file is what
the cockpit renders as progress.

**Gating stops and waits.** It fires on these, and you do not get to decide that
one of them does not count:

| Trigger | |
|---|---|
| More than `gate.max_files` files touched (default 4) | A change reaching five files is not a fix, whatever it was called when it started |
| A path matching `gate.guarded` | Blast radius, not size. One line in a permission check outweighs fifty in a component |
| A new dependency | A maintenance tail the operator owns, not you |
| A user-facing surface | It owes a proof and a flow sync |
| Any file deleted | Least reversible thing you can do |
| It contradicts a numbered decision in `.delivery/decisions.md` | Flag it, never silently override |
| The intent has two readings that produce different work | The only judgement call on this list. Ask |

`gate-check.sh` enforces the first two mechanically on every write and
**re-evaluates as scope grows** — a task that starts at one file and reaches
five stops at five. When it denies you, declare, get approval
(`checklist.sh approve <slice>` records it), then continue. Do not work around
it. The remaining triggers are yours to honour; the operator saying *go* to a
declaration approves the work on the table and nothing beyond it.

## The loop for any intent

```
intent → STEP 0: declare checklist (+ gate if triggered)
      → dm-architect (spec + slices) → GATE 1: operator approves plan
      → per slice: dm-builder → dm-reviewer → dm-verifier (proof/)
      → GATE 2: operator reviews proof → done; branch handed over
```

- **Gates stop and wait.** Present the plan / the proof folder, then ask. Never present-and-proceed.
- **Log a `dispatched` line before an agent runs**, not only after it finishes:
  `bash "$DM_PLUGIN/scripts/run-log.sh" dm-builder <slice> dispatched "round 1"`. An agent
  nobody has logged is invisible — the operator sees a silence and cannot tell working from stuck.
- On verifier FAIL → back to the same builder with the failure. Log the loop.
- **Two rounds, then it is the operator's call.** A third failure does not go back to the
  builder: open Gate 2 carrying the failure instead of the proof and let them decide whether
  to keep pushing. "Loop until the proof holds" with no bound is an unbounded spend with no
  human in it.
- After each agent completes, log it through the ledger script — never by hand:
  `bash "$DM_PLUGIN/scripts/run-log.sh" dm-builder <slice> built "<note>"` (reviewer: `reviewed`/`failed`,
  builder fixing a rejection: `fixed`). `done` is written only as
  `bash "$DM_PLUGIN/scripts/run-log.sh" dm-verifier <slice> done "<note>"` after the verifier has written
  `proof/<slice>/README.md`; the script refuses it from anyone else, or when the README is older than the
  slice's newest commit. A refused run-log means the slice is not done — go back to the builder.
- Gate 2 is opened with `bash "$DM_PLUGIN/scripts/dm-gate.sh" <slice>`: it re-checks the proof is fresh, writes
  `gate-<slice>-proof.txt` to the inbox and pings the phone. If it exits 2, there is no gate — fix the proof first.
  The orchestrator never writes `runs.jsonl` or a Gate 2 file by hand.
  After the operator merges the branch, the next `orchestrator.sh` run prunes its worktree (`dm-prune.sh`: merged and clean only; branches stay).
- Decisions the operator makes get a numbered line in `.delivery/decisions.md` (`D-<n>: <decision> — <date>`).
- At Gate 1, also push a phone notification: `bash "$DM_PLUGIN/scripts/notify.sh" "GATE: <what's waiting>"` (`dm-gate.sh` does this for Gate 2).

## Agent dispatch — decide yourself, never ask

| Work | Do |
|---|---|
| Trivial (one file, obvious, < ~30 min) | Do it inline yourself — no agents, no spec, no gate. **Still declare it** (step 0); three lines is a fine checklist. Still verify + proof if user-facing. "No ceremony" never means "no declaration". |
| A feature / multi-file change | Full loop above. |
| 2+ independent slices | Builders in parallel, each in its own git worktree. |
| Pure research/exploration | An Explore/general agent; summarize, no build machinery. |

## Model routing — decide yourself, never ask

Already pinned in the agent definitions: architect=opus, builder/reviewer/verifier=sonnet. For ad-hoc subagents you spawn: haiku for mechanical lookups and bulk file listing; sonnet for ordinary coding and research; opus only for architecture-grade reasoning. Never ask the operator which model to use.

## Stopping the machine

The operator closing their laptop, or saying "stop everything", means
`bash "$DM_PLUGIN/scripts/dm-stop.sh"` from the project root: it writes the handoff,
stops the services, kills the machine's tmux session and marks the registry stopped so the
fleet page does not claim a dead machine is running. `--pause` is the same minus the kill —
services down, session and ledger kept, for stepping away for an hour. Never leave them to
work out which windows to `C-c` by hand.

One limit to state plainly rather than imply otherwise: **this reaches the local machine
only.** A cloud session writes the same `.delivery/` files and so appears in the ledger, but
nothing here can stop it.

## Stopping / restarting services

The operator can stop, restart, or start any service directly from its tile on the dashboard (▮ / ↻ buttons — no session needed, instant). So if they ask you in chat to "stop the services", you may do it too via `tmux send-keys -t dm-<project>:<window> C-c`, but ALWAYS write a one-line confirmation to `.delivery/replies/` so they see it happened on the dashboard — a silent action reads as "nothing happened". The same rule holds for any action taken from a `note-*`: reply so the outcome is visible.

## The tmux law

You and every agent NEVER run a server, database, watcher, or anything long-lived in background Bash. It goes through `bash "$DM_PLUGIN/scripts/dm-run.sh" <window> <cmd>` into the visible machine. Read logs with `tmux capture-pane -p -t dm-<project>:<window>`.

## Proof-of-done

A feature is done when `proof/<slice>/` exists with verifier-generated screenshots and a README mapping each artifact to the claim it proves, `run-log.sh … dm-verifier <slice> done` accepted it, and the operator has approved the gate `dm-gate.sh` opened (Gate 2). Never report done without it. Never fabricate proof.

The step-0 checklist and the proof are the same object seen from both ends: every item's
`proof` field named what would demonstrate it, and `proof/<slice>/README.md` is where those
demonstrations land. An unchecked item at Gate 2 is not an oversight, it is the answer —
the slice is not done.

## Session rotation

Handoffs are automatic — the PreCompact hook writes `.delivery/HANDOFF.md`, the Stop hook
refreshes it, and SessionStart re-injects it. PreCompact alone was not enough: it only fires
on compaction, so closing a terminal left nothing behind and the operator had to ask for a
handoff every time. Your only job: when context feels heavy (~80%), finish the current step
cleanly — never start a new slice; the next session picks it up from the handoff, with the
open checklist beside it.

## Skill foundry

Config-gated: `foundry` in `config.json`, default true. A project that sets it false gets
none of this, and that is a reasonable choice for a codebase whose skills are authored
deliberately. Where it is on, `foundry.sh` runs on every Stop and writes `.delivery/skill-candidates/cand-*.md` when a pattern shows up 3+ times in `runs.jsonl` / `config-miss.log`. At session start, if candidates exist, review them: if one genuinely deserves a reusable skill, author it in `.claude/skills/` (writing-skills flow) and delete the candidate; otherwise delete it. Never let candidates pile up unreviewed.

## Always-on pickup

The orchestrator runs `watch.sh` in the `watch` window. When inbox items appear: if a `claude*` window exists in the machine, the watcher types `/dm process the pending items in .delivery/inbox` into it (at most once per two minutes — Claude queues the line if it is mid-turn), so a gate answered from the dashboard reaches the session that is waiting at that gate. If no session exists anywhere, it dispatches a headless `claude -p "/dm process inbox"` on the project's `claude_config_dir`. A session running outside the machine (heartbeat only) is left alone — it has no window to type into.

## Terminals in mission control

Every tmux window of the machine is a live terminal tile on the dashboard (ttyd). Sessions started with `dm.sh` or the dashboard's "+ session" button get a tile too; anything an agent starts through `dm-run.sh` appears as one automatically.

## Config-first constitution (for projects that adopt it)

If the project's CLAUDE.md declares config-first: no feature merges without its tunable values externalized to configuration and defaults recorded. The reviewer checks this.
