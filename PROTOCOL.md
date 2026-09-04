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

Three more optional keys. All are defaulted, so an existing `config.json` keeps behaving
exactly as it did:

| key | default | read by | means |
|---|---|---|---|
| `gate` | `{"max_files":4,"guarded":["run-log.sh","proof-fresh.sh","hooks.json"]}` | `gate-check.sh` | when a task must stop and declare a checklist. `guarded` entries are globs, matched against the whole path, its basename, and `*/<glob>` |
| `knowledge_paths` | `[".claude/knowledge/**","docs/decisions/**"]` | `knowledge-log.sh` | globs whose writes are worth recording. Absolute globs and `~` are allowed, which is how a write under a Claude config dir's `memory/` gets caught |
| `foundry` | `true` | `foundry.sh` | `false` makes the Stop-hook skill foundry a no-op. Only an explicit `false` disables it — a missing key, a missing file or unparseable JSON all keep it on |

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
{"ts":"<iso>","agent":"orchestrator|dm-<role>","slice":"<name>","status":"dispatched|working|built|reviewed|fixed|failed|done","note":"<short>"}
```
`dispatched` is the one status logged *before* the work: this agent has been handed this slice
and is running now. Every other status is logged after the fact, which left an in-flight agent
invisible — the ledger only ever spoke about finished work. It carries no proof rule and never
satisfies `done`; a slice whose last line is `dispatched` is running, not finished. The runtime
also treats the slice on the ledger's last line as the slice currently in flight (`gate-check.sh`).

`agent` is `orchestrator` or `dm-<role>` in lowercase — the four stock roles are `dm-architect`,
`dm-builder`, `dm-reviewer`, `dm-verifier`, and a project may add its own (`dm-scenario-writer`).
Exactly these five fields; no others.

Written by `run-log.sh <agent> <slice> <status> <note>`. `done` is accepted only from `dm-verifier`
and only while `proof/<slice>/README.md` is at least as new as the newest commit on a branch named
`<slice>` or `*/<slice>` (HEAD if none) — `proof-fresh.sh`. A bad agent, an unknown status, or a
`done` without fresh proof exits 2 and writes nothing.

Nothing can *stop* an agent with a shell from appending to this file directly, so the guarantee is
made checkable rather than claimed: `ledger-verify.sh` re-reads the ledger and reports any line
run-log.sh would not have written, including a `done` whose proof has since gone stale. Entries at
or before `.delivery/ledger-baseline` (one ISO timestamp, written by `ledger-verify.sh --accept`)
are summarised as history instead of listed.

## `.delivery/decisions.md`
`D-<n>: <decision> — <YYYY-MM-DD>`, appended by the orchestrator when the operator decides.

## `.delivery/checklist/<slice>.json` — what a gated slice promised
```json
{ "slice": "<name>",
  "intent": "<one line — the operator's ask, verbatim where possible>",
  "gated": true,
  "triggers": ["files>4", "guarded:src/shared/auth/can.ts"],
  "approved_at": "<iso>|null",
  "items": [ {"text": "what will be done", "proof": "what will demonstrate it",
              "done": false, "ts": null} ] }
```
Written only by `checklist.sh init|add|check|approve <slice>` (`show` prints it). `add` refuses an
item with an empty `proof`: an item that never said what would demonstrate it cannot honestly be
checked off, so the field is required at the moment the item is written, not filled in later.
`check <slice> <index>` takes the 0-based index of `items` and sets `done` + `ts`. `approve` stamps
`approved_at`, and that stamp is the *only* thing `gate-check.sh` reads — an unapproved checklist
opens nothing.

## `.delivery/knowledge.log`
Append-only, one tab-separated line per knowledge write: `<iso>\t<path>\t<write|edit>` (`write`
for the `Write` tool, `edit` for `Edit` and `NotebookEdit`). `<path>` is what the tool reported,
verbatim. Written by `knowledge-log.sh` from a `PostToolUse` hook on `Write|Edit|NotebookEdit`,
and only for paths matching `config.json` `knowledge_paths`. Silent outside a Janus project and
on every non-match, so this file is a list of knowledge writes and nothing else. The case it
exists for is a write under a Claude config dir's `memory/`: outside any git repo, so without
this line the write leaves no trace at all.

## `.delivery/.touched` — the scope gate's working set
One path per line, one line per distinct file this session has written to; appended by
`gate-check.sh` on every `Write|Edit|NotebookEdit` and removed by `session-start.sh`, so the
count is per session. `gate-check.sh` re-checks it on **every** call, not once at the start:
a task that begins as one file and reaches five stops at five. Denial is a `PreToolUse`
`permissionDecision: "deny"` whose reason tells the agent to declare a checklist and get the
operator to approve it; an approved checklist for the slice in flight lifts it.

The slice in flight is the one named by the ledger's last line — the only record of what is
running. With no ledger there is no such slice, so any approved checklist counts; otherwise a
project that never logs a run could declare a checklist and still not be able to proceed.

Deliberately fails open. Bad hook JSON, no `python3`, an unparseable `config.json` — anything
it cannot understand — exits 0 and lets the write through, noting the failure in
`.delivery/pickup.log`. A gate that blocks every edit when it breaks takes the machine down and
reads to the operator as Claude hanging.

## `.delivery/agents/<sid>.json` — heartbeats
Written by the `activity.sh` hook on every event: `{"sid","ts","event","detail","role","cwd"}`.
A session is *live* if any heartbeat is younger than 120 s (`is-live.sh`). Swept after 30 min.

## `.delivery/activity.jsonl`
Same events, appended, capped at ~1200 lines. Read-only for the dashboard's activity views.

## `.delivery/HANDOFF.md`
Written by `handoff.sh` on **PreCompact and Stop**, injected by SessionStart. Free-form markdown.
PreCompact alone only fires on compaction, so closing a terminal left a handoff hours out of date
and the operator had to ask for a fresh one. `dm-stop.sh` writes it first, before it stops
anything.

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
`{ "<project>": { "dir", "session", "port", "ttyd_port", "started", "state"?, "stopped"? } }`.
Written by the orchestrator; read by the fleet page, `janus.sh` and `dm-boot.sh`.

`state` is `"stopped"` or `"paused"`, with `stopped: <iso>`, and is written by `dm-stop.sh` —
the entry itself is never deleted, because the fleet page still lists the machine. It marks a
machine switched off on purpose: without it the registry claims a machine killed before a reboot
is still running, and `dm-boot.sh` restarts it at login as though it had crashed. `dm-boot.sh`
skips a `stopped`/`paused` machine; `janus.sh` shows the state instead of guessing. Starting the
machine again rewrites the whole entry (`orchestrator.sh`), which clears both fields.

## HTTP (mission control only)
`GET /api/state` (everything above as JSON) · `POST /api/inbox {kind:"reply"|"note", re, text}` ·
`POST /api/service {window, action:"start"|"stop"|"restart"}` · `POST /api/session` ·
`GET /api/logs?w=` · `GET /api/activity?sid=` · `GET /api/fleet` · `GET /events` (SSE nudge).
Nothing here is required by the agent layer.
