---
name: dm-init
description: Initialize Janus in the current project — one-time scaffold. Use when the user says "set up Janus here", "/dm-init", or /dm finds no .delivery/config.json.
---

# dm-init — one-time project scaffold

1. **Detect the project**: name from the directory; candidate services from `package.json` scripts (dev/start/api/web/worker), `docker-compose*.yml` services, or a Makefile. Propose the service map; ask the operator to confirm/correct it in ONE question. A project with no services yet gets an empty map — the machine still runs mission control.

2. **Write `.delivery/config.json`**:
```json
{
  "project": "<dir-name>",
  "services": { "<name>": "<command>" },
  "claude_config_dir": null,
  "ntfy_topic": null
}
```
`claude_config_dir`: set only when this project uses a different Claude account (see dm-remote for ntfy_topic).

3. **Scaffold** (create only what's missing): `.delivery/inbox/` (empty, with a `.gitkeep`), `.delivery/decisions.md` (header line), `.delivery/runs.jsonl` (empty), `.planning/specs/`, `.planning/notes/`, `proof/`.

4. **Gitignore**: append `.delivery/HANDOFF.md` and `.delivery/inbox/` to `.gitignore` (session-local state); `decisions.md`, `runs.jsonl`, `.planning/`, `proof/` are committed — they are the track record.

5. **Project CLAUDE.md**: if one exists, append a short "Janus" section pointing at the /dm skill and the tmux law; if none, offer to create a minimal one.

6. **CI proof**: if `git remote -v` shows a GitHub remote and `.github/workflows/dm-proof.yml` does not exist, copy `$DM_PLUGIN/templates/dm-proof.yml` there and tell the operator it runs `pnpm -r test` on `fix/**`, `feat/**` and PRs — edit the test step if the project's command differs. No GitHub remote → say it can be added later with the same file.

7. Finish by starting the machine: `bash "$DM_PLUGIN/scripts/orchestrator.sh"` and report the mission-control URL — and that future sessions start with `bash "$DM_PLUGIN/scripts/dm.sh"` so they run inside the machine and get a terminal tile.
