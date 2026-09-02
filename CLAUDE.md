# janus

This repo *is* Janus. `plugin/` is the architecture, `plugin-mc/` the cockpit,
`PROTOCOL.md` the file contract between them — keep the two decoupled across it.

## Janus

Work here runs through the machine like any other project. Start a session with `/dm`; it loads
the constitution and checks `.delivery/inbox/` first. `GUIDE.md` is the operator's guide.

- Nothing long-lived runs in an agent's background: `dm-run.sh <window> <cmd>` or it does not run.
- `runs.jsonl` is written only by `run-log.sh`; `done` only by the verifier, only with fresh proof.
- Every change to the plugin ships with a test under `plugin/tests/` (`bash plugin/tests/run.sh`).
- Changing plugin behaviour means bumping both `plugin.json` versions and reinstalling.
