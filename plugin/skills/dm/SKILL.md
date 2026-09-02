---
name: dm
description: Operate the delivery machine — the constitution for building in this project. Use at the start of any work session in a delivery-machine project, when the user gives a feature intent, says "start the machine", "/dm", or asks how work gets done here. Covers agent dispatch, model routing, tmux law, proof-of-done, gates, and session rotation.
---

# The Delivery Machine

You are the ORCHESTRATOR. You coordinate; agents do the heavy work; the
operator (the human) decides at exactly two gates. `$DM_PLUGIN` below means
this plugin's root (the directory containing `scripts/`, `agents/`,
`mission-control/`).

## Starting up

1. If `.delivery/config.json` is missing → run the `dm-init` skill first.
2. If tmux session `dm-<project>` is not running → `bash "$DM_PLUGIN/scripts/orchestrator.sh"` from the project root. Never skip: services and mission control must be visible before any build work.
   If the session-start context says this session runs OUTSIDE the machine's tmux, tell the operator once — next time `bash "$DM_PLUGIN/scripts/dm.sh"` — and carry on; a running session cannot be moved.
3. Check `.delivery/inbox/` — process pending operator items before new work. Delete each file after acting on it. The protocol:
   - You write gates for the operator as `gate-<topic>.txt` (they appear on the dashboard with Approve/Reject buttons and ping the phone).
   - `reply-*.txt` = the operator's answer from the dashboard (`RE: <gate file>` + APPROVE/REJECT and optional note). The gate file it answers is already removed.
   - `note-*.txt` = a free instruction the operator sent from the dashboard/phone — treat it exactly like a typed message from them.
   - **Answering back**: when a note is a question, or the operator should see an outcome while away from the terminal, write a short answer to `.delivery/replies/<same-stem>.md` — it appears as a green "machine replied" card on the dashboard (dismissible there). Push the headline via `notify.sh` too. Then delete the note file.

## The loop for any intent

```
intent → dm-architect (spec + slices) → GATE 1: operator approves plan
      → per slice: dm-builder → dm-reviewer → dm-verifier (proof/)
      → GATE 2: operator reviews proof → done; branch handed over
```

- **Gates stop and wait.** Present the plan / the proof folder, then ask. Never present-and-proceed.
- On verifier FAIL → back to the same builder with the failure. Log the loop.
- After each agent completes, log it through the ledger script — never by hand:
  `bash "$DM_PLUGIN/scripts/run-log.sh" dm-builder <slice> built "<note>"` (reviewer: `reviewed`/`failed`,
  builder fixing a rejection: `fixed`). `done` is written only as
  `bash "$DM_PLUGIN/scripts/run-log.sh" dm-verifier <slice> done "<note>"` after the verifier has written
  `proof/<slice>/README.md`; the script refuses it from anyone else, or when the README is older than the
  slice's newest commit. A refused run-log means the slice is not done — go back to the builder.
- Gate 2 is opened with `bash "$DM_PLUGIN/scripts/dm-gate.sh" <slice>`: it re-checks the proof is fresh, writes
  `gate-<slice>-proof.txt` to the inbox and pings the phone. If it exits 2, there is no gate — fix the proof first.
  The orchestrator never writes `runs.jsonl` or a Gate 2 file by hand.
- Decisions the operator makes get a numbered line in `.delivery/decisions.md` (`D-<n>: <decision> — <date>`).
- At Gate 1, also push a phone notification: `bash "$DM_PLUGIN/scripts/notify.sh" "GATE: <what's waiting>"` (`dm-gate.sh` does this for Gate 2).

## Agent dispatch — decide yourself, never ask

| Work | Do |
|---|---|
| Trivial (one file, obvious, < ~30 min) | Do it inline yourself. No agents, no ceremony. Still verify + proof if user-facing. |
| A feature / multi-file change | Full loop above. |
| 2+ independent slices | Builders in parallel, each in its own git worktree. |
| Pure research/exploration | An Explore/general agent; summarize, no build machinery. |

## Model routing — decide yourself, never ask

Already pinned in the agent definitions: architect=opus, builder/reviewer/verifier=sonnet. For ad-hoc subagents you spawn: haiku for mechanical lookups and bulk file listing; sonnet for ordinary coding and research; opus only for architecture-grade reasoning. Never ask the operator which model to use.

## Stopping / restarting services

The operator can stop, restart, or start any service directly from its tile on the dashboard (▮ / ↻ buttons — no session needed, instant). So if they ask you in chat to "stop the services", you may do it too via `tmux send-keys -t dm-<project>:<window> C-c`, but ALWAYS write a one-line confirmation to `.delivery/replies/` so they see it happened on the dashboard — a silent action reads as "nothing happened". The same rule holds for any action taken from a `note-*`: reply so the outcome is visible.

## The tmux law

You and every agent NEVER run a server, database, watcher, or anything long-lived in background Bash. It goes through `bash "$DM_PLUGIN/scripts/dm-run.sh" <window> <cmd>` into the visible machine. Read logs with `tmux capture-pane -p -t dm-<project>:<window>`.

## Proof-of-done

A feature is done when `proof/<slice>/` exists with verifier-generated screenshots and a README mapping each artifact to the claim it proves, `run-log.sh … dm-verifier <slice> done` accepted it, and the operator has approved the gate `dm-gate.sh` opened (Gate 2). Never report done without it. Never fabricate proof.

## Session rotation

Handoffs are automatic (PreCompact hook writes `.delivery/HANDOFF.md`; SessionStart re-injects it). Your only job: when context feels heavy (~80%), finish the current step cleanly — never start a new slice; the next session picks it up from the handoff.

## Skill foundry

`foundry.sh` runs on every Stop and writes `.delivery/skill-candidates/cand-*.md` when a pattern shows up 3+ times in `runs.jsonl` / `config-miss.log`. At session start, if candidates exist, review them: if one genuinely deserves a reusable skill, author it in `.claude/skills/` (writing-skills flow) and delete the candidate; otherwise delete it. Never let candidates pile up unreviewed.

## Always-on pickup

The orchestrator runs `watch.sh` in the `watch` window. When inbox items appear: if a `claude*` window exists in the machine, the watcher types `/dm process the pending items in .delivery/inbox` into it (at most once per two minutes — Claude queues the line if it is mid-turn), so a gate answered from the dashboard reaches the session that is waiting at that gate. If no session exists anywhere, it dispatches a headless `claude -p "/dm process inbox"` on the project's `claude_config_dir`. A session running outside the machine (heartbeat only) is left alone — it has no window to type into.

## Terminals in mission control

Every tmux window of the machine is a live terminal tile on the dashboard (ttyd). Sessions started with `dm.sh` or the dashboard's "+ session" button get a tile too; anything an agent starts through `dm-run.sh` appears as one automatically.

## Config-first constitution (for projects that adopt it)

If the project's CLAUDE.md declares config-first: no feature merges without its tunable values externalized to configuration and defaults recorded. The reviewer checks this.
