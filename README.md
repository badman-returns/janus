# Delivery Machine

Portable agentic delivery workflow as a Claude Code plugin: architect/builder/
reviewer/verifier agents with two human approval gates, every service visible
in tmux, proof-of-done screenshots, a live mission-control dashboard, automatic
session handoffs, and a fleet registry across projects.

Design: `bongbrix/products/unified-platform/design/2026-09-02-delivery-machine-hld.md`

## Install (once per Claude account)

```bash
claude plugin marketplace add ~/Documents/rootman/delivery-machine
claude plugin install delivery-machine@dm-marketplace     # the architecture: agents, gates, ledger, machine
claude plugin install mission-control@dm-marketplace      # the cockpit (optional) — live terminals, cards, fleet
```

For a second account, run the same two commands from a session on that account
(or with its `CLAUDE_CONFIG_DIR` active).

## Use in any project

```
cd <project>
claude
> /dm-init        # one time: detects services, scaffolds .delivery/ .planning/ proof/
```

Then, every session:

```
bash <plugin>/scripts/dm.sh [--resume <id>]   # machine up, a Claude INSIDE it, attached
> /dm                                          # operate the machine
```

`dm.sh` is what gives the session a terminal tile in mission control. A Claude
started outside the machine's tmux still works but is invisible to the dashboard
(the session-start hook says so). More sessions: the "+ session" button on the
dashboard, or `dm.sh` again — windows `claude`, `claude-2`, `claude-3`…

The orchestrator alone: `bash <plugin>/scripts/orchestrator.sh` from the project root.

- Mission control: `http://localhost:<port>` (auto-assigned per project, auto-opens; every dashboard links to the whole fleet)
- Attach to the runtime: `tmux attach -t dm-<project>`
- Phone / remote / push: `/dm-remote`

## Boot at login

`bash <plugin>/scripts/install-login.sh` installs a launchd agent
(`~/Library/LaunchAgents/com.delivery-machine.boot.plist`) that runs `dm-boot.sh` at login:
every project in `~/.delivery-machine/registry.json` that still has a `.delivery/` comes up,
no terminal needed (log: `~/.delivery-machine/boot.log`). `install-login.sh --remove` takes it out.

macOS blocks launchd agents from `~/Documents`, `~/Desktop` and `~/Downloads` (the log shows
`Operation not permitted`). If the plugin or a project lives there, grant **Full Disk Access** to
`/bin/bash` once (System Settings → Privacy & Security → Full Disk Access → `+` → ⌘⇧G → `/bin/bash`),
then `launchctl kickstart -k gui/$(id -u)/com.delivery-machine.boot`.

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
