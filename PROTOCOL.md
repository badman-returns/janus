# The file protocol

Everything in Janus talks through files in the project and tmux window names.
The agent layer (skills, agents, hooks), the machine runtime (orchestrator, watcher), and mission
control (the dashboard) share nothing else. Any of the three can be replaced as long as these
shapes hold.

All paths are relative to the project root. Timestamps are ISO-8601 UTC unless noted.

## `.delivery/config.json`

```json
{ "project": "<name>", "services": { "<window>": "<command>" },
  "claude_config_dir": "~/.claude-x" | null, "ntfy_topic": "<topic>" | null }
```
`project` names the tmux session `dm-<project>`. `services` become windows. `claude_config_dir`
is exported as `CLAUDE_CONFIG_DIR` for every Claude the machine starts.

Optional: `"secrets": { "<ENV_VAR>": "<name>", ... }`. Each value names a macOS keychain generic
password `dm:<project>:<name>` whose password is the base64 of the secret (`security add-generic-password
-a "$USER" -s "dm:<project>:<name>" -w "$(base64 < file)" -U`). When the map is non-empty, every service
window and every `dm-run.sh` command is prefixed with `eval "$(bash <plugin>/scripts/secrets-env.sh)"`,
which exports each entry; a missing item is a warning on stderr, never a failure. Values are never
written to any file.

## `.delivery/inbox/` — the only write path from operator to machine

| file | written by | body | consumed by |
|---|---|---|---|
| `gate-<topic>.txt` | orchestrator (Gate 1); `dm-gate.sh` as `gate-<slice>-proof.txt` (Gate 2) | plain text: what is waiting, APPROVE/REJECT instructions | operator (dashboard, phone, or `echo` into a reply) |
| `ask-<ms>-<slug>.txt` | `ask.sh` hook | JSON `{"kind":"ask"\|"permission","title":…,"questions":[{"question":…,"options":[…],"multi":bool}]}` | operator |
| `reply-<ms>-<slug(name)>.txt` | operator | line 1 `RE: <gate or ask filename>`, rest = answer (`APPROVE`, `REJECT: note`, option label, `ALLOW`, `DENY: note`) | orchestrator (gates), `ask.sh` (asks) — the consumer deletes it |
| `note-<ms>-<slug>.txt` | operator | free text, treated as a typed message | orchestrator |
| `handled/` | watcher | items a headless run left behind | nobody; audit only |

Writing a reply removes the gate/ask it answers. `<slug>` = lowercase, `[^a-z0-9-]`→`-`, 40 chars.
`ask.sh` matches replies on the ask's `<ms>` timestamp, so slug truncation cannot break it.

## `.delivery/replies/<stem>.md`
Machine → operator prose. One markdown file per answer; the dashboard shows it as a card and
`POST /api/replies/dismiss` deletes it.

## `.delivery/runs.jsonl` — the ledger
One JSON object per line, appended only:
```json
{"ts":"<iso>","agent":"dm-architect|dm-builder|dm-reviewer|dm-verifier","slice":"<name>","status":"working|built|reviewed|fixed|failed|done","note":"<short>"}
```
Written only by `run-log.sh <agent> <slice> <status> <note>`. `done` is accepted only from
`dm-verifier` and only while `proof/<slice>/README.md` is at least as new as the newest commit on a
branch named `<slice>` or `*/<slice>` (HEAD if none) — `proof-fresh.sh`. Anything else exits 2 and
writes nothing.

## `.delivery/decisions.md`
`D-<n>: <decision> — <YYYY-MM-DD>`, appended by the orchestrator when the operator decides.

## `.delivery/agents/<sid>.json` — heartbeats
Written by the `activity.sh` hook on every event: `{"sid","ts","event","detail","role","cwd"}`.
A session is *live* if any heartbeat is younger than 120 s (`is-live.sh`). Swept after 30 min.

## `.delivery/activity.jsonl`
Same events, appended, capped at ~1200 lines. Read-only for the dashboard's activity views.

## `.delivery/HANDOFF.md`
Written by the PreCompact hook, injected by SessionStart. Free-form markdown.

## `.planning/specs/*.md`, `.planning/notes/*.md`
Architect output. Listed by the dashboard; no shape is imposed.

## `proof/<slice>/`
Verifier output: screenshots and a `README.md` mapping each artifact to the claim it proves.
A slice is done when `run-log.sh … done` accepted this and the operator has approved the gate that
`dm-gate.sh <slice>` opened (Gate 2). `dm-gate.sh` applies the same freshness rule and writes no gate
file when it fails.

## tmux
Session `dm-<project>`. Window names are the contract: `control`, one per service, `mission`,
`watch`, `ttyd`, `claude`, `claude-2`… Anything long-lived goes through `dm-run.sh <window> <cmd>`.
Dashboard tiles are windows; `ttyd ?arg=<window>` attaches a private grouped view to one.

## `~/.delivery-machine/registry.json`
`{ "<project>": { "dir", "session", "port", "ttyd_port", "started" } }`. Written by the
orchestrator; read by the fleet page and `dm-boot.sh`.

## HTTP (mission control only)
`GET /api/state` (everything above as JSON) · `POST /api/inbox {kind:"reply"|"note", re, text}` ·
`POST /api/service {window, action:"start"|"stop"|"restart"}` · `POST /api/session` ·
`GET /api/logs?w=` · `GET /api/activity?sid=` · `GET /api/fleet` · `GET /events` (SSE nudge).
Nothing here is required by the agent layer.
