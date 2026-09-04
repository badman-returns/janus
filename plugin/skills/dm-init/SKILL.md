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
  "ntfy_topic": null,
  "proof_dir": "proof",
  "foundry": true,
  "gate": { "max_files": 4, "guarded": [] },
  "knowledge_paths": [".claude/knowledge/**", "docs/decisions/**"]
}
```
`claude_config_dir`: set only when this project uses a different Claude account (see dm-remote for ntfy_topic).
`proof_dir`: where `proof/<slice>/` lives, when it should not sit at the machine's root — e.g. `"../docs/proof"` for a machine running in a subdirectory.
`gate.guarded`: globs whose blast radius outweighs their size, so any edit to one stops for approval regardless of how small it is. Ask the operator for these — auth, permission checks, the API URL map, CI workflows and whatever their lint standard is enforced by. An empty list means only the file count triggers.
`knowledge_paths`: globs whose edits get logged to `.delivery/knowledge.log`, so "did the knowledge actually update?" has an answer. Absolute paths are allowed, and are the way to catch writes to a memory directory outside any repo.

3. **Scaffold** (create only what's missing): `.delivery/inbox/` (empty, with a `.gitkeep`), `.delivery/decisions.md` (header line), `.delivery/runs.jsonl` (empty), `.planning/specs/`, `.planning/notes/`, `proof/`.

4. **Gitignore**: append `.delivery/HANDOFF.md` and `.delivery/inbox/` to `.gitignore` (session-local state); `decisions.md`, `runs.jsonl`, `.planning/`, `proof/` are committed — they are the track record.

5. **Project CLAUDE.md**: if one exists, append a short "Janus" section pointing at the /dm skill and the tmux law; if none, offer to create a minimal one.

6. **CI proof**: if `git remote -v` shows a GitHub remote and `.github/workflows/dm-proof.yml` does not exist, copy `$DM_PLUGIN/templates/dm-proof.yml` there. **The template is pnpm; adapt it before you leave it.** Read the lockfile to find out what the project actually uses — `yarn.lock` → yarn (`yarn install --frozen-lockfile`, and drop the pnpm action), `package-lock.json` → `npm ci`, `pnpm-lock.yaml` → leave it as-is — and set the test step to the project's real command. A workflow for the wrong package manager fails on first push, which is worse than no workflow. If the project already has CI that runs the tests, say so and skip this step rather than adding a second one. No GitHub remote → say it can be added later with the same file.

7. Finish by starting the machine: `bash "$DM_PLUGIN/scripts/orchestrator.sh"` and report the mission-control URL — and that future sessions start with `bash "$DM_PLUGIN/scripts/dm.sh"` so they run inside the machine and get a terminal tile.
