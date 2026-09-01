# Delivery Machine

Portable agentic delivery workflow as a Claude Code plugin: architect/builder/
reviewer/verifier agents with two human approval gates, every service visible
in tmux, proof-of-done screenshots, a live mission-control dashboard, automatic
session handoffs, and a fleet registry across projects.

Design: `bongbrix/products/unified-platform/design/2026-09-02-delivery-machine-hld.md`

## Install (once per Claude account)

```bash
claude plugin marketplace add ~/Documents/rootman/delivery-machine
claude plugin install delivery-machine@dm-marketplace
```

For a second account, run the same two commands from a session on that account
(or with its `CLAUDE_CONFIG_DIR` active).

## Use in any project

```
cd <project>
claude
> /dm-init        # one time: detects services, scaffolds .delivery/ .planning/ proof/
> /dm             # every session: operate the machine
```

The orchestrator can also be started straight from a terminal:
`bash <plugin>/scripts/orchestrator.sh` from the project root.

- Mission control: `http://localhost:<port>` (auto-assigned per project, auto-opens; every dashboard links to the whole fleet)
- Attach to the runtime: `tmux attach -t dm-<project>`
- Phone / remote / push: `/dm-remote`

## What the operator does

Give intent → approve the architect's plan (gate 1) → review the generated
proof (gate 2) → merge branches when ready. Everything else — agent choice,
model choice, parallelism, handoffs — the machine decides.

## Layout

```
plugin/
  agents/           dm-architect (opus) · dm-builder · dm-reviewer · dm-verifier (sonnet)
  skills/           dm (the constitution) · dm-init · dm-remote
  hooks/hooks.json  PreCompact → HANDOFF.md · SessionStart → inject handoff+status
  scripts/          orchestrator.sh · dm-run.sh · handoff.sh · session-start.sh · notify.sh
  mission-control/  server.js + index.html (zero-dependency, reads the project's own files)
```

Per-project state: `.delivery/` (config, inbox, decisions, runs, handoff),
`.planning/` (specs, notes), `proof/` (verifier evidence). Fleet registry:
`~/.delivery-machine/registry.json`.
