#!/usr/bin/env python3
"""Send-only Telegram poster for the fleet. Reads what the machines already write and never polls
Telegram (ccgram owns getUpdates for this bot). Every pass:
  - new lines in each machine's runs.jsonl -> one headline each
  - new gate-*/ask-* files in each inbox   -> one card each, once
  - files in each .delivery/outbox/        -> sent by type, moved to outbox/sent/
  - a slice dispatched > 30 min ago with a live heartbeat -> "still working", at most hourly
State: ~/.delivery-machine/feed-state.json. Usage: fleet-feed.py [--once] [--interval 5] [--say TEXT]
Env: TELEGRAM_BOT_TOKEN, FEED_CHAT_ID, FEED_THREAD_ID (optional), TELEGRAM_API_BASE (tests)."""
import json, os, sys, time, glob, shutil, mimetypes, uuid, urllib.request, urllib.parse, pathlib

HOME = pathlib.Path.home()
STATE = HOME / ".delivery-machine/feed-state.json"
REG = HOME / ".delivery-machine/registry.json"
TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT = os.environ.get("FEED_CHAT_ID", "")
THREAD = os.environ.get("FEED_THREAD_ID", "").strip()
if THREAD == "0": THREAD = ""          # topics are optional: unset or 0 = the chat's default topic
API = os.environ.get("TELEGRAM_API_BASE", "https://api.telegram.org").rstrip("/")
SEND_AS = {".png": "sendPhoto", ".jpg": "sendPhoto", ".jpeg": "sendPhoto", ".mp4": "sendVideo",
           ".ogg": "sendVoice", ".oga": "sendVoice"}
FIELD = {"sendPhoto": "photo", "sendVideo": "video", "sendVoice": "voice", "sendDocument": "document"}
SILENCE_S, SILENCE_REPEAT_S = 30 * 60, 60 * 60

def load_state():
    try: return json.loads(STATE.read_text())
    except Exception: return {"offsets": {}, "announced": [], "silence": {}}

def save_state(s):
    STATE.parent.mkdir(parents=True, exist_ok=True); STATE.write_text(json.dumps(s))

def api(method, fields, filepath=None, filefield=None):
    if not TOKEN or not CHAT: return False
    fields = dict(fields, chat_id=CHAT)
    if THREAD: fields["message_thread_id"] = THREAD
    url = f"{API}/bot{TOKEN}/{method}"
    for attempt in range(3):
        try:
            if filepath:
                b = uuid.uuid4().hex.encode(); body = b""
                for k, v in fields.items():
                    body += b"--" + b + b'\r\nContent-Disposition: form-data; name="' + k.encode() + b'"\r\n\r\n' + str(v).encode() + b"\r\n"
                ctype = mimetypes.guess_type(filepath)[0] or "application/octet-stream"
                body += (b"--" + b + b'\r\nContent-Disposition: form-data; name="' + filefield.encode() + b'"; filename="'
                         + os.path.basename(filepath).encode() + b'"\r\nContent-Type: ' + ctype.encode() + b"\r\n\r\n")
                body += pathlib.Path(filepath).read_bytes() + b"\r\n--" + b + b"--\r\n"
                req = urllib.request.Request(url, body, {"Content-Type": "multipart/form-data; boundary=" + b.decode()})
            else:
                req = urllib.request.Request(url, urllib.parse.urlencode(fields).encode())
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode()).get("ok", False)
        except Exception as e:
            time.sleep(2 ** attempt)
            err = e
    safe = str(err).replace(TOKEN, "<token>") if TOKEN else str(err)   # never print the token
    print(f"telegram failed: {method}: {safe}", file=sys.stderr); return False

def headline(note, n=120):
    first = note.strip().split(". ")[0].split("\n")[0]
    return (first if len(first) <= n else first[: n - 1] + "…").rstrip(".") + ("." if "." in note[: len(first) + 1] else "")

def machines():
    try: return {k: v["dir"] for k, v in json.loads(REG.read_text()).items() if os.path.isdir(v.get("dir", ""))}
    except Exception: return {}

def ledger(proj, d, state):
    p = pathlib.Path(d) / ".delivery/runs.jsonl"
    if not p.exists(): return
    off = state["offsets"].get(p.as_posix(), 0)
    data = p.read_bytes()
    if len(data) < off: off = 0
    for line in data[off:].decode(errors="ignore").splitlines():
        try: e = json.loads(line)
        except Exception: continue
        api("sendMessage", {"text": f"{proj} · {e.get('slice','?')} · {e.get('agent','?')} {e.get('status','?')} · {headline(e.get('note',''))}"})
    state["offsets"][p.as_posix()] = len(data)

def gates(proj, d, state):
    for f in sorted(glob.glob(f"{d}/.delivery/inbox/gate-*.txt") + glob.glob(f"{d}/.delivery/inbox/ask-*.txt")):
        key = f"{proj}:{os.path.basename(f)}"
        if key in state["announced"]: continue
        body = pathlib.Path(f).read_text(errors="ignore")[:1500]
        if os.path.basename(f).startswith("ask-"):
            try: q = json.loads(body); body = q.get("title", "") + "\n" + "\n".join(f"- {x.get('question')}: {' | '.join(x.get('options', []))}" for x in q.get("questions", []))
            except Exception: pass
        # plain text, no parse_mode: gate bodies are arbitrary operator prose and would break Markdown
        if api("sendMessage", {"text": f"⏸ {proj} · waiting on you\n{body}\n\nAnswer here: /gate approve {proj}  or  /gate reject {proj} <why>"}):
            state["announced"].append(key)

def outbox(proj, d):
    ob = pathlib.Path(d) / ".delivery/outbox"
    if not ob.is_dir(): return
    (ob / "sent").mkdir(exist_ok=True)
    for f in sorted(p for p in ob.iterdir() if p.is_file() and p.suffix != ".caption"):
        cap = f.with_name(f.name + ".caption")
        caption = (cap.read_text().strip() if cap.exists() else f"{proj} · {f.name}")[:1024]
        if f.suffix.lower() in (".md", ".txt") and f.stat().st_size < 3500:
            ok = api("sendMessage", {"text": f"{proj} · {f.name}\n\n" + f.read_text(errors='ignore')})
        else:
            method = SEND_AS.get(f.suffix.lower(), "sendDocument")
            if f.stat().st_size > 50 * 1024 * 1024:
                ok = api("sendMessage", {"text": f"{proj} · {f.name} is over 50 MB and stays on disk: {f}"})
            else:
                ok = api(method, {"caption": caption}, str(f), FIELD[method])
        if ok:
            shutil.move(str(f), ob / "sent" / f.name)
            if cap.exists(): cap.unlink()

def silence(proj, d, state):
    p = pathlib.Path(d) / ".delivery/runs.jsonl"
    if not p.exists(): return
    try: last = json.loads(p.read_text(errors="ignore").strip().splitlines()[-1])
    except Exception: return
    if last.get("status") != "dispatched": return
    age = time.time() - time.mktime(time.strptime(last["ts"], "%Y-%m-%dT%H:%M:%SZ")) + time.timezone
    beats = glob.glob(f"{d}/.delivery/agents/*.json")
    live = any(time.time() - os.path.getmtime(b) < 120 for b in beats)
    key = f"{proj}:{last.get('slice')}"
    if age > SILENCE_S and time.time() - state["silence"].get(key, 0) > SILENCE_REPEAT_S:
        api("sendMessage", {"text": f"⏳ {proj} · {last.get('slice')} · {last.get('agent')} dispatched {int(age//60)} min ago · " + ("still working" if live else "no heartbeat — check the machine")})
        state["silence"][key] = time.time()

def one_pass():
    state = load_state()
    for proj, d in machines().items():
        ledger(proj, d, state); gates(proj, d, state); outbox(proj, d); silence(proj, d, state)
    save_state(state)

if __name__ == "__main__":
    interval = float(sys.argv[sys.argv.index("--interval") + 1]) if "--interval" in sys.argv else 5.0
    if "--say" in sys.argv:                      # one-shot: post this line and exit, no pass
        rest = sys.argv[sys.argv.index("--say") + 1:]
        if not rest: sys.exit("usage: fleet-feed.py --say <text>")
        ok = api("sendMessage", {"text": rest[0]})
        print("sent" if ok else "not sent"); sys.exit(0 if ok else 1)
    if "--once" in sys.argv: one_pass(); sys.exit(0)
    print("fleet-feed running", flush=True)
    while True:
        one_pass(); time.sleep(interval)
