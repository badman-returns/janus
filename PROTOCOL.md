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
is exported as `CLAUDE_CONFIG_DIR` for every Claude the machine starts, and is also the machine's
seat: `office` when it resolves to `~/.claude-alt`, `personal` otherwise (`fleet-status.sh` prints
which).

Three more optional keys. All are defaulted, so an existing `config.json` keeps behaving
exactly as it did:

| key | default | read by | means |
|---|---|---|---|
| `gate` | `{"max_files":4,"guarded":["run-log.sh","proof-fresh.sh","hooks.json"]}` | `gate-check.sh` | when a task must stop and declare a checklist. `guarded` entries are globs, matched against the whole path, its basename, and `*/<glob>` |
| `knowledge_paths` | `[".claude/knowledge/**","docs/decisions/**"]` | `knowledge-log.sh` | globs whose writes are worth recording. Absolute globs and `~` are allowed, which is how a write under a Claude config dir's `memory/` gets caught |
| `foundry` | `true` | `foundry.sh` | `false` makes the Stop-hook skill foundry a no-op. Only an explicit `false` disables it — a missing key, a missing file or unparseable JSON all keep it on |
| `memory_dataset` | `"<project>"` | `dm-session.sh` | the Cognee dataset every session opened inside this machine carries as `COGNEE_PLUGIN_DATASET`; defaults to `project`. Rooms are datasets one to one, so recall never crosses a room; a machine on the employer seat has its own |
| `pickup_skill` | `"dm"` | `pickup-line.sh` for `watch.sh`; the voice loop reads the key itself and types the same line | which skill answers a machine's inbox when a nudge is typed in — `concierge` on the fleet machine, `dm` everywhere else. A typed `/word` only ever reaches a session when it names a registered skill |

Optional: `"secrets": { "<ENV_VAR>": "<name>", ... }`. Each value names a macOS keychain generic
password `dm:<project>:<name>` whose password is the base64 of the secret (`security add-generic-password
-a "$USER" -s "dm:<project>:<name>" -w "$(base64 < file)" -U`). When the map is non-empty, every service
window and every `dm-run.sh` command is prefixed with `eval "$(bash <plugin>/scripts/secrets-env.sh)"`,
which exports each entry; a missing item is a warning on stderr, never a failure. Values are never
written to any file.

The fleet machine's config carries one more optional key, `voice`, read by the voice loop
(`voice/loop.py`) and the shell (`voice/shell.py`): `{ mic, wake_model, whisper_url, kokoro_voice,
hotkey, partials, port, vad, vad_rms, echo_margin, wake_settle, wake_threshold_speaking,
min_speech, think_timeout }`. Every key is defaulted — a missing key, or no `voice` object at all,
starts the loop on the built-in microphone and the stand-in wake word. Defaults: `mic` `"1"`,
`wake_model` `"hey_jarvis"`, `kokoro_voice` `"am_michael"`, `hotkey`
`"alt+space"`, `partials` `true`, `port` `8790`, `vad` `"silero"`, `vad_rms` `0.015`, `echo_margin`
`1.8`, `wake_settle` `1.5s`, `wake_threshold_speaking` `0.8`, `min_speech` `0.4s`, `think_timeout`
`120s`.

## `.delivery/inbox/` — the only write path from operator to machine

| file | written by | body | consumed by |
|---|---|---|---|
| `gate-<topic>.txt` | orchestrator (Gate 1); `dm-gate.sh` as `gate-<slice>-proof.txt` (Gate 2) | plain text: what is waiting, APPROVE/REJECT instructions | operator (dashboard, phone, or `echo` into a reply) |
| `ask-<ms>-<slug>.txt` | `ask.sh` hook | JSON `{"kind":"ask"\|"permission","title":…,"questions":[{"question":…,"options":[…],"multi":bool}]}` | operator |
| `reply-<ms>-<slug(name)>.txt` | operator | line 1 `RE: <gate or ask filename>`, rest = answer (`APPROVE`, `REJECT: note`, option label, `ALLOW`, `DENY: note`) | orchestrator (gates), `ask.sh` (asks) — the consumer deletes it |
| `note-<ms>-<slug>.txt` | operator | free text, treated as a typed message | orchestrator |
| `note-<ms>-voice-<slug>.txt`, `note-<ms>-tg-<slug>.txt`, or any note carrying a `from:` first line | the voice loop (`from: voice <iso>` spoken, `from: typed <iso>` the Talk box), `fleet-route.sh` (`from: telegram <iso>`), the loop relaying another machine's answer (`from: relay <machine> <iso>`) | optional second line `interrupted: <what was being said>`, then a blank line, then the text | orchestrator — identical consumption to any note; the header is provenance only |
| `handled/` | watcher | items a headless run left behind | nobody; audit only |

Writing a reply removes the gate/ask it answers. `<slug>` = lowercase, `[^a-z0-9-]`→`-`, 40 chars.
`ask.sh` matches replies on the ask's `<ms>` timestamp, so slug truncation cannot break it.

## `.delivery/replies/<stem>.md`
Machine → operator prose. One markdown file per answer; the dashboard shows it as a card and
`POST /api/replies/dismiss` deletes it. The front page's `/api/front` reads the newest few the same
way, and the voice loop watches this directory for the file named after the note it is waiting on.

May start with header lines, each `key: value`, then a blank line: `via: <machine>` when the
content came from another machine's session and is only relayed here; `speak: yes|no` forces or
forbids the voice loop speaking it regardless of the standing policy; `needs: <machine> <gate-or-ask
file>` means the reply ends in a question only the operator can answer, and puts the loop into its
`waiting` state about that card. A reply with none of these headers is unchanged: prose, nothing
more.

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

Where the slice has a UI, also `proof.mp4` (a narrated screen recording assembled by
`proof-video.sh` from Playwright scenes) and `narration.md` (one sentence per scene); the same
freshness rule applies, the video is evidence beside the README, not instead of it. `review.md` is
the reviewer's three to five sentences on the order to read the diff; `review.html` is that guide
rendered over the diff with diff2html, built by `dm-gate.sh` and gitignored — regenerate it, never
commit it.

## `.delivery/outbox/` — files for the operator

Anything any agent, `dm-gate.sh`, or a scheduled job decides the operator should have and cannot
hand over any other way: a screenshot, a proof video, a rendered document, a voice message.

| path | written by | consumed by | rule |
|---|---|---|---|
| `.delivery/outbox/<ms>-<slug>.{png,jpg,mp4,pdf,md,txt,ogg}` (+ optional `.caption` sidecar) | any agent, `dm-gate.sh`, a job | `fleet-feed.py`, which sends it by type and moves it to `outbox/sent/` | never a secret, never production data; the caption is one line, sent as the file's caption |

A file Telegram refuses outright lands in `outbox/sent/<name>.rejected` — visible, never retried; a
transient failure is left where it is and retried on the next pass. `<ms>-<job>-failed.txt` is how
a scheduled job (`brief.sh`, `miner.sh`) reports its own `claude` run failing, so a silent skipped
morning is instead heard on the phone.

## `~/.brain/` — the fleet machine's flags, queue and job log

Outside any one project, read by the concierge, the voice loop, the desk speaker and the jobs.

| path | means |
|---|---|
| `PAUSED` | every scheduled job checks this first (`job-guard.sh`) and exits 0 immediately when it exists; gates and replies keep flowing while paused, only the jobs stop |
| `voice.on` | the desk speaker may speak unsolicited output; expires two hours after it is set |
| `dnd` | silences the wake word and the desk speaker; a turn started with the hotkey is still answered aloud |
| `meeting` | the same silence as `dnd`, set by the operator around a call |
| `voice-queue/<ms>.txt` | one file per queued utterance for the desk speaker (`voice-say.sh`), oldest first, deleted once spoken |
| `jobs.log` | one line per scheduled job's run, success or failure |
| `reports/<employee>/latest.md` | written by an employee (its own spec) after each run; the front page's employees row shows the first line of each, empty text until a report exists |
| `foundry/wt` | the foundry loop's own worktree for the round in progress, rebuilt fresh from the default branch every time; the operator's own checkout is never touched |

## `foundry/` — the nightly loop's own files (`dm-janus` only)

`foundry/program.md` is what the operator edits to steer the loop; `foundry/log.md`, one line
appended per round (keep or revert, and why), is gitignored — it is the loop's scratch, not part of
the plugin, and is never committed.

## tmux
Session `dm-<project>`. Window names are the contract: `control`, one per service, `mission`,
`watch`, `ttyd`, `claude`, `claude-2`… Anything long-lived goes through `dm-run.sh <window> <cmd>`.
Dashboard tiles are windows; `ttyd ?arg=<window>` attaches a private grouped view to one.

`bridge` is a tmux session that holds linked copies of every machine's `claude*` window
(`bridge-link.sh`). It is not a machine: it has no `.delivery/`, appears in no registry, and the
only consumer is the Telegram bridge. On the fleet machine, `voice` and `shell` are service windows
like any other — the voice loop and the menu-bar/hotkey/pill process — restarted the same way when
`orchestrator.sh` finds them at their prompt.

## `~/.delivery-machine/registry.json`
`{ "<project>": { "dir", "session", "port", "ttyd_port", "started", "state"?, "stopped"? } }`.
Written by the orchestrator; read by the fleet page, `janus.sh` and `dm-boot.sh`.

`state` is `"stopped"` or `"paused"`, with `stopped: <iso>`, and is written by `dm-stop.sh` —
the entry itself is never deleted, because the fleet page still lists the machine. It marks a
machine switched off on purpose: without it the registry claims a machine killed before a reboot
is still running, and `dm-boot.sh` restarts it at login as though it had crashed. `dm-boot.sh`
skips a `stopped`/`paused` machine; `janus.sh` shows the state instead of guessing. Starting the
machine again rewrites the whole entry (`orchestrator.sh`), which clears both fields.

One entry, keyed `fleet`, is the fleet machine itself: the brain repo, registered exactly like any
project. Nothing in this shape marks it different — only its window names do (`bridge`, `whisper`,
`feed`, `voice`, `shell`).

## Scripts worth knowing by name

Every script below is under `plugin/scripts/`; each carries a rule worth stating once, here, rather
than only in its own header comment.

| script | does |
|---|---|
| `type-line.sh` | types one line into a Claude window and presses Enter, only when its input box is empty; exit 3 when the box holds a draft (clear or send it there first), exit 2 when there is no input line to type into |
| `service-alive.sh` | tells a service window sitting at its tmux prompt (Ctrl-C'd, or crashed) from one actually running something; `orchestrator.sh` restarts whatever it finds at its prompt |
| `machine-dir.sh` | resolves a registered machine's directory by name from the registry; the name is checked in the shell and passed to Python as an argument, never interpolated into source |
| `fleet-status.sh` | one line per registered machine: seat, liveness, last ledger line, waiting gates, checklist progress |
| `fleet-route.sh` | writes an operator note into a machine's inbox, tagged `from: telegram` |
| `fleet-gate.sh` | answers a machine's gate or ask the way the dashboard does, appending `.delivery/threads/<gate>.md` before removing it; `--re <card>` names which card, and with more than one waiting it refuses (exit 3) and lists them; `latest` answers the newest gate on any registered machine; verdicts are case-insensitive |
| `inflight.sh` | JSON of every slice actually in flight, for the feeder to check a meeting's decisions against |
| `bridge-link.sh` / `bridge-run.sh` | link every machine's `claude*` window into the `bridge` tmux session, and run ccgram bound to it; `DM_BRIDGE=0` switches the bridge off entirely (what the tests set) |
| `fleet-feed.py` | send-only Telegram poster: ledger transitions, gate cards and outbox files, sent by type, retried on a transient failure, `.rejected` on a permanent one |
| `proof-video.sh` | assembles `proof/<slice>/proof.mp4` from Playwright scenes and `narration.md`, narrated and burned in as captions |
| `tts-ogg.sh` | renders text to an Opus `.ogg` voice file for a Telegram voice message |
| `voice-say.sh` | the desk speaker: one queue, opt-in, machine-prefixed, yields to the voice loop while it is listening, thinking or speaking |
| `brief.sh` / `miner.sh` / `lint-job.sh` / `install-jobs.sh` | the 07:00 brief, the 02:00 miner, the weekly wiki lint, and the launchd installer for all four jobs; the default set installed with no job named is `brief lint` — `miner` and `foundry` are named on purpose |
| `foundry-loop.sh` | autoresearch for Janus: one change per round in its own worktree and branch, kept or reverted by the fixed eval, logged, never merged |
| `identity-check.sh` | refuses a session whose git identity or Claude account does not match the mapped identity for this path, and prints the fix |
| `job-guard.sh` | sourced by every scheduled job; exits 0 immediately when `~/.brain/PAUSED` exists |

## HTTP (mission control only)
Nothing here is required by the agent layer — the cockpit is one reader of the files above and
can be replaced without touching anything else. But the page is the only consumer of these
routes, so a change here that is not written down is a change nobody can find.

| route | shape |
|---|---|
| `GET /api/state` | everything above, as one JSON object. The page fetches it once and refetches on every `/events` nudge, so **new data goes here** rather than into a new route |
| `GET /api/slice?name=` | one slice's whole story: `{slice, runs[], spec, decisions[], branch:{name,commits[]}, proof, gates[], checklist}`. `400` on a name outside `[\w.-]+` |
| `GET /api/logs?w=` | `tmux capture-pane` for one window, as text |
| `GET /api/activity?sid=` | that session's hook events, newest first |
| `GET /api/fleet` | the registry plus, per machine, `alive` and `waiting` |
| `GET /events` | SSE. Any change under `.delivery/`, `.planning/` or the proof dir, plus a 5 s tick |
| `POST /api/inbox` | `{kind:"reply"\|"note", re, text}` — writes `reply-*`/`note-*`, and for a reply to a `gate-*` also appends the thread and deletes the gate |
| `POST /api/replies/dismiss` | `{name}` — deletes one `.delivery/replies/<name>` |
| `POST /api/service` | `{window, action:"start"\|"stop"\|"restart"}` |
| `POST /api/session` | a new Claude inside the machine (`dm-session.sh`) |
| `POST /api/machine` | `{action:"stop"\|"pause"}` — runs `dm-stop.sh` (with `--pause`) from the project root. Anything else is `400` |
| `GET /api/front` | the front page's whole state: every registered machine's alive/seat/state, its newest gates and asks with their bodies, its last few ledger lines, its newest replies, its checklist progress, and each employee's latest report headline |
| `POST /api/front/reply`, `POST /api/front/note` | `{project, re, text}` / `{project, text}` — same as `/api/inbox`, addressed at a machine other than the fleet machine itself |
| `POST /api/front/open` | `{project, slice}` — `code -r` on that slice's worktree if one exists, else the machine's root |
| `GET /api/front/proof?project=&file=` | serves a file under that machine's proof dir, with Range support (`206`, or `416` past the end) — what the front page's `<video>` scrubs |
| `GET /front`, `GET /pill` | the one screen and the pill, served as static pages |

The voice loop's own endpoint, `127.0.0.1:8790` on the fleet machine, is a separate process and not
part of mission control — no route above reaches it. `GET /stream` (SSE; events `state`, `level`,
`you`, `janus`, `false_alarm`), `GET /state`, `POST /say`, `POST /listen`, `POST /stop`. The front
page reads it directly: the orb, the Talk column and the title bar have no other source.

### `/api/state`, field by field
The names the cockpit's five bands read. `project`, `session`, `now`, `ttyd_port`, `account`,
`usage`, `git`, `tmux`, `specs`, `notes`, `proof`, `runs`, `inbox`, `replies`, `activity`,
`agents`, `threads`, `decisions`, `handoff`, `fleet` — plus:

| field | is |
|---|---|
| `checklist` | an array of **every** `.delivery/checklist/<slice>.json`, newest file first, each verbatim. Every slice's, not one: the in-flight band joins them to the ledger by `slice`, and the checklist panel picks the slice named by the ledger's last line — the same slice `gate-check.sh` calls in flight |
| `knowledge` | `{writes, paths[], diffstat}`. `paths[]` is `knowledge.log` grouped by path, newest write first: `{path, count, last, kinds[], outside}`. `outside` means the path resolves above the project root — a memory write, with no commit and no diff anywhere, which is the case the log exists for. `diffstat` is `git diff --stat` over the repo-local paths only (up to 40), because those are the only ones git can speak about |
| `handoff_mtime` | ISO mtime of `.delivery/HANDOFF.md`, or `null` when there is none. The age, not the body — `handoff` still carries the text. `dm-stop.sh` writes the handoff first, so a fresh age is also how the page shows a stop or pause completed |

### `POST /api/machine` and the response that must outlive the machine
`stop` kills the tmux session mission control itself runs in. So the response is written and
flushed **before** the script starts (`res.end(body, cb)`), and `dm-stop.sh` is then started
`detached` — its own process group, so the signal tmux sends to this pane never reaches it.
A synchronous `execSync` here dies mid-response and the operator sees a network error instead
of a confirmation. After a `stop` the page goes offline, which is the success path; after a
`pause` the server survives, because `mission` is not one of `config.json` `services`.
