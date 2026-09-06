#!/usr/bin/env python3
"""Janus's voice loop. Runs as the fleet machine's `voice` service from the fleet machine's root
(the brain repo). Hears the microphone through ffmpeg, wakes to the name (openWakeWord), bounds an
utterance (Silero through openWakeWord, or an RMS gate), transcribes it with the fleet's
whisper-server, writes it as a voice note into .delivery/inbox and nudges the concierge, watches
.delivery/replies for the answer, speaks it with Kokoro one sentence at a time through afplay, and
can be interrupted. Every change is one event on http://127.0.0.1:8790/stream. State lives in
state.py; this file only does what the machine says."""
import glob, io, json, os, queue, re, subprocess, sys, threading, time, urllib.request, uuid, wave
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from state import Machine
from speech import split_header, sentences

ROOT = os.getcwd()
def _config():
    try: return json.load(open(os.path.join(ROOT, '.delivery', 'config.json')))
    except Exception: return {}
CONF = _config(); C = CONF.get('voice', {}) or {}
MIC = str(C.get('mic', '1')); PORT = int(C.get('port', 8790)); WAKE = C.get('wake_model', 'hey_jarvis')
VOICE = C.get('kokoro_voice', os.environ.get('KOKORO_VOICE', 'am_michael')); PARTIALS = bool(C.get('partials', True))
WHISPER = C.get('whisper_url', 'http://127.0.0.1:8178/v1/audio/transcriptions')
VAD_MODE = C.get('vad', 'silero'); RMS_ON = float(C.get('vad_rms', 0.015))    # ponytail: one knob, tune at the desk
ECHO_MARGIN = float(C.get('echo_margin', 1.8))    # how far over its own echo a voice must be to be someone else
SESSION = 'dm-' + CONF.get('project', 'fleet'); PICKUP = CONF.get('pickup_skill', 'dm')
BRAIN = os.path.expanduser('~/.brain'); os.makedirs(os.path.join(BRAIN, 'voice', 'failed'), exist_ok=True)
SR = 16000; FRAME = 1280            # 80 ms frames: what openWakeWord wants

# ---- the stream: every reader gets every event ----
class Stream:
    def __init__(self): self.subs = set(); self.lock = threading.Lock(); self.last_state = {'t': 'state', 'state': 'idle'}
    def emit(self, ev):
        if ev.get('t') == 'state': self.last_state = ev
        line = 'data: ' + json.dumps(ev) + '\n\n'
        with self.lock:
            for q in list(self.subs):
                try: q.put_nowait(line)
                except queue.Full: pass
    def subscribe(self):
        q = queue.Queue(maxsize=400)
        with self.lock: self.subs.add(q)
        return q
    def unsubscribe(self, q):
        with self.lock: self.subs.discard(q)
stream = Stream()

# ---- audio in: ffmpeg → 16 kHz mono int16 frames; three silent restarts mean no permission ----
def mic_frames(on_dead):
    cmd = ['ffmpeg', '-loglevel', 'quiet', '-f', 'avfoundation', '-i', f':{MIC}', '-ac', '1', '-ar', str(SR), '-f', 's16le', '-']
    dead = 0
    while True:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE); got = False
        while True:
            b = p.stdout.read(FRAME * 2)
            if len(b) < FRAME * 2: break
            got = True; dead = 0; yield np.frombuffer(b, dtype=np.int16)
        dead += 0 if got else 1
        if dead >= 3: on_dead(); dead = 0; time.sleep(30)
        time.sleep(0.5)

def rms(f): return float(np.sqrt(np.mean((f.astype(np.float32) / 32768.0) ** 2)) + 1e-9)
def make_wake():
    from openwakeword.model import Model
    return Model(wakeword_models=[WAKE], inference_framework='onnx')
def make_vad():
    if VAD_MODE == 'silero':
        try:
            from openwakeword.vad import VAD
            v = VAD(); v.predict(np.zeros(FRAME, dtype=np.int16))
            return lambda f: float(v.predict(f)) > 0.5
        except Exception as e: print('vad: silero unavailable, using the rms gate:', e, file=sys.stderr)
    return lambda f: rms(f) > RMS_ON

# ---- whisper ----
def wav_bytes(frames):
    buf = io.BytesIO(); w = wave.open(buf, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(np.concatenate(frames).tobytes()); w.close(); return buf.getvalue()
def transcribe(frames):
    body = wav_bytes(frames); b = 'janus' + uuid.uuid4().hex
    data = (f'--{b}\r\nContent-Disposition: form-data; name="file"; filename="a.wav"\r\nContent-Type: audio/wav\r\n\r\n').encode() + body + \
           (f'\r\n--{b}\r\nContent-Disposition: form-data; name="model"\r\n\r\nwhisper-1\r\n--{b}--\r\n').encode()
    req = urllib.request.Request(WHISPER, data=data, headers={'Content-Type': f'multipart/form-data; boundary={b}'})
    with urllib.request.urlopen(req, timeout=30) as r: return json.loads(r.read().decode()).get('text', '').strip()

# ---- notes and replies ----
def slugify(s): return re.sub(r'[^a-z0-9-]+', '-', (s or '').lower())[:40].strip('-') or 'voice'
def write_note(stem, text, cut_stem, cut_index, source='voice'):
    d = os.path.join(ROOT, '.delivery', 'inbox'); os.makedirs(d, exist_ok=True)
    hdr = f"from: {source} {time.strftime('%Y-%m-%dT%H:%M:%S')}\n"
    if cut_stem: hdr += f"interrupted: {cut_stem} at {cut_index}\n"
    with open(os.path.join(d, stem + '.txt'), 'w') as f: f.write(hdr + '\n' + text + '\n')
    threading.Thread(target=nudge, daemon=True).start()   # tmux is not allowed to hold the machine's lock
def nudge():
    """What watch.sh would type on its next poll, typed now: a spoken question cannot wait twenty seconds.
    The line names the machine's pickup skill (`pickup_skill` in config.json, `dm` when unset), so a
    machine with a concierge is asked in its own words instead of being handed a build intent."""
    try:
        wins = subprocess.run(['tmux', 'list-windows', '-t', SESSION, '-F', '#{window_id} #W'], capture_output=True, text=True, timeout=5).stdout.splitlines()
        w = next((x.split()[0] for x in wins if len(x.split()) > 1 and x.split()[1].startswith('claude')), None)
        if not w: return
        # by id (a name two windows share is ambiguous to tmux), through type-line.sh: a line left unsent
        # in the session's box would be submitted together with ours, so it refuses and says why
        r = subprocess.run(['bash', os.path.join(os.path.dirname(HERE), 'plugin', 'scripts', 'type-line.sh'), w,
                            f'/{PICKUP} process the pending items in .delivery/inbox'], capture_output=True, text=True, timeout=15)
        if r.returncode: print('nudge held:', r.stderr.strip(), file=sys.stderr); return
        open(os.path.join(ROOT, '.delivery', '.nudge'), 'w').write(str(int(time.time())))
    except Exception as e: print('nudge failed:', e, file=sys.stderr)
def reply_dirs():
    """The fleet's own replies, and every other registered machine's. The concierge routes an office
    question with fleet-route.sh; that machine answers into its own .delivery/replies, and until now
    nothing carried the answer back to the desk. ponytail: the registry is read once, so a machine
    registered later needs a loop restart — re-reading it would also have to seed `seen` per dir."""
    own = os.path.realpath(os.path.join(ROOT, '.delivery', 'replies')); dirs = {own: None}
    try: reg = json.load(open(os.path.expanduser('~/.delivery-machine/registry.json')))
    except Exception as e: print('registry:', e, file=sys.stderr); return dirs
    for name, m in reg.items():
        try: dirs.setdefault(os.path.realpath(os.path.join(m.get('dir', ''), '.delivery', 'replies')), name)
        except Exception as e: print('registry entry', name, 'skipped:', e, file=sys.stderr)   # one bad entry never kills the watcher
    return dirs                                               # the fleet's own dir is already in, and stays None
def watch_replies(on_reply):
    os.makedirs(os.path.join(ROOT, '.delivery', 'replies'), exist_ok=True)   # only ours; another machine's is its own
    dirs = reply_dirs(); seen = {p for d in dirs for p in glob.glob(os.path.join(d, '*.md'))}
    while True:
        try:
            fresh = []
            for d, machine in dirs.items():
                for p in glob.glob(os.path.join(d, '*.md')):
                    if p in seen: continue
                    try: mt = os.path.getmtime(p)
                    except OSError: continue                  # gone between the glob and the stat
                    if time.time() - mt < 0.3: continue       # still being written; read it next pass
                    fresh.append((mt, p, machine))
            for _, p, machine in sorted(fresh):
                try: txt = open(p, encoding='utf-8').read()
                except Exception: continue                    # not readable yet: no `seen`, so we try again
                seen.add(p)
                h, body = split_header(txt)
                if machine:                                   # another machine's answer to a question we routed
                    h = dict(h, via=machine)                  # its name, whatever the file claims
                    write_note(f"note-{int(time.time() * 1000)}-relay-{slugify(machine)}-{slugify(body)}",
                               body.strip(), None, None, 'relay ' + machine)   # so the concierge has it in context
                on_reply(os.path.basename(p)[:-3], sentences(body), h)
        except Exception as e: print('reply watcher:', e, file=sys.stderr)
        time.sleep(0.25)

# ---- speaking: one mouth. A worker plays one afplay at a time, so a bridge never talks over a sentence,
# and it renders i+1 while i plays. afplay is the process we end to pause. ----
class Player:
    def __init__(self, on_done):
        self.on_done = on_done; self.proc = None; self.cache = {}; self.lock = threading.Lock(); self.gen = 0
        self.play_level = 0.0; self.play_t0 = 0.0     # what the room is being given right now, and since when; 0 when quiet
        self.inflight = {}; self.rendering = 0        # one tts.sh per wav, and a count for the stranded-speaking watchdog
        self.q = queue.Queue(); threading.Thread(target=self._worker, daemon=True).start()
    def render(self, key, text):
        """The wav for one sentence or bridge, rendered once however many callers want it. None if tts failed."""
        with self.lock:
            if key in self.cache: return self.cache[key]
            ev = self.inflight.get(key); mine = ev is None
            if mine: ev = self.inflight[key] = threading.Event()
        if not mine: ev.wait(60); return self.cache.get(key)
        out = os.path.join(BRAIN, 'voice', f'{key[0]}-{key[1]}.wav')
        with self.lock: self.rendering += 1
        try:
            if os.path.exists(out) and os.path.getsize(out) > 44:  # a bridge an earlier run already said; sentence keys are unique
                with self.lock: self.cache[key] = out
                return out
            r = subprocess.run(['bash', os.path.join(HERE, 'tts.sh'), text, out, VOICE], capture_output=True)
            ok = r.returncode == 0 and os.path.exists(out) and os.path.getsize(out) > 44
            if not ok: print('tts failed for %r: rc=%s %s' % (text[:40], r.returncode, r.stderr[-200:]), file=sys.stderr)
            with self.lock:
                if ok: self.cache[key] = out
            return out if ok else None
        finally:                          # a raise must not leave the key in flight for ever, or the count high
            with self.lock: self.rendering -= 1; self.inflight.pop(key, None)
            ev.set()
    @staticmethod
    def envelope(path):
        try:
            w = wave.open(path, 'rb'); sr = w.getframerate(); a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0; w.close()
            win = max(1, sr // 30); return [float(np.sqrt(np.mean(a[i:i + win] ** 2))) for i in range(0, len(a), win)]
        except Exception: return []
    def say(self, kind, rid, i, text, sents=None):
        """Queue one thing to be said. kind 'sentence' advances the machine when it ends; 'bridge' does not."""
        with self.lock: self.q.put((self.gen, kind, rid, i, text, sents))
    def busy(self):
        return bool(self.rendering) or not self.q.empty() or (self.proc is not None and self.proc.poll() is None)
    def _worker(self):
        while True:
            item = self.q.get()
            try: self._play(*item)
            except Exception as e: print('playback failed:', e, file=sys.stderr)
    def _play(self, gen, kind, rid, i, text, sents):
        if gen != self.gen: return                                  # a pause or a stop passed this by
        path = self.render((rid, i), text)
        if path is None:                                            # tts is down: say so on the stream, do not strand
            stream.emit({'t': 'janus', 'text': '(a sentence could not be rendered)', 'bridge': True})
            if kind == 'sentence': self.on_done()
            return
        if sents and i + 1 < len(sents): threading.Thread(target=self.render, args=((rid, i + 1), sents[i + 1]), daemon=True).start()
        env = self.envelope(path); t0 = time.time()
        with self.lock:
            if gen != self.gen: return
            self.proc = subprocess.Popen(['afplay', path]); self.play_t0 = t0
        while self.proc.poll() is None:
            k = int((time.time() - t0) * 30); self.play_level = env[k] if k < len(env) else 0.0
            stream.emit({'t': 'level', 'v': round(min(1.0, self.play_level * 4), 3)}); time.sleep(1 / 30)
        self.play_level = 0.0; self.play_t0 = 0.0
        stream.emit({'t': 'level', 'v': 0.0})
        if kind == 'sentence' and gen == self.gen and self.proc.returncode == 0: self.on_done()
    def pause(self):
        with self.lock:
            self.gen += 1
            while True:
                try: self.q.get_nowait()
                except queue.Empty: break
            if self.proc and self.proc.poll() is None: self.proc.terminate()

# ---- the loop: performs the machine's actions; owns the microphone policy ----
class Loop:
    def __init__(self):
        self.m = Machine(); self.replies = {}; self.player = Player(self.sentence_done); self.lock = threading.RLock()
        self.mic_open = False; self.buf = []; self.silence = 0; self.speech = 0; self.opened_at = 0.0; self.last_partial = 0.0
        self.flags = {'dnd': False, 'meeting': False, 'voice_on': False}; self.said_working = False
        self.echo = 0.0; self.echo_rid = None           # how loudly the room hands Janus back his own voice
        self.finishing = False                          # a transcript is in flight: `listening` with a shut mic is expected
        self.source = 'voice'; self.idle_speak = 0; self.idle_listen = 0
    def feed(self, ev, **kw):
        with self.lock:
            if ev in ('stop', 'offline'): self.player.pause()       # nothing queued outlives a stop
            if ev in ('speech_end', 'typed'): self.source = 'voice' if ev == 'speech_end' else 'typed'
            self.act(self.m.feed(ev, **kw))
    def act(self, actions):
        for a in actions:
            k = a[0]
            if k == 'state':
                info = {x: y for x, y in a[2].items() if x != 'since'}; stream.emit({'t': 'state', 'state': a[1], **info}); self.said_working = False
            elif k == 'open_mic': self.buf = []; self.silence = 0; self.speech = 0; self.opened_at = time.time(); self.last_partial = time.time(); self.mic_open = True
            elif k == 'close_mic': self.mic_open = False; stream.emit({'t': 'level', 'v': 0.0})
            elif k == 'pause_playback': self.player.pause()
            elif k in ('speak', 'resume_playback'):
                sents = self.replies[a[1]]
                if k == 'speak': stream.emit({'t': 'janus', 'reply': a[1], 'i': a[2], 'text': sents[a[2]]})
                self.player.say('sentence', a[1], a[2], sents[a[2]], sents)
            elif k == 'write_note': write_note(a[1], a[2], a[3], a[4], self.source)
            elif k == 'show_reply': stream.emit({'t': 'janus', 'reply': a[1], 'sentences': a[2], 'via': a[3], 'spoken': a[4]})
            elif k == 'say_bridge':
                stream.emit({'t': 'janus', 'text': a[1], 'bridge': True}); self.player.say('bridge', 'bridge', slugify(a[1]), a[1])
    def sentence_done(self): self.feed('sentence_done')
    def on_reply(self, stem, sents, h):
        self.replies[stem] = sents
        self.feed('reply', stem=stem, sentences=sents, speak=h.get('speak'), via=h.get('via'), needs=h.get('needs'))
    def mic_dead(self):
        self.feed('offline'); print('voice: no audio from the microphone; grant Microphone access to the terminal app in System Settings → Privacy & Security', file=sys.stderr)
    def audio(self):
        try: wake = make_wake(); vad = make_vad()
        except Exception as e:
            print('voice: the wake model or the vad would not load:', e, file=sys.stderr); self.feed('offline'); return
        prev = None
        for f in mic_frames(self.mic_dead):
            if self.m.state == 'offline': self.feed('online')
            st = self.m.state
            if prev == 'speaking' and st != 'speaking': wake.reset()      # no score half-heard over his own voice
            prev = st
            if self.mic_open:
                with self.lock:
                    if not self.mic_open: continue                        # closed under us between the test and the lock
                    self.buf.append(f); talking = vad(f)
                    stream.emit({'t': 'level', 'v': round(min(1.0, rms(f) * 8), 3)})
                    if talking: self.speech += 1; self.silence = 0
                    else: self.silence += 1
                    now = time.time()
                    if PARTIALS and self.speech > 3 and now - self.last_partial > 1.5:
                        self.last_partial = now; threading.Thread(target=self.partial, args=(list(self.buf),), daemon=True).start()
                    if (self.speech > 0 and self.silence >= 9) or now - self.opened_at > 20 or (self.speech == 0 and now - self.opened_at > 4):
                        frames = list(self.buf); had = self.speech > 0; self.mic_open = False; self.finishing = True
                        stream.emit({'t': 'level', 'v': 0.0})            # the meter stops with the microphone, not with the transcript
                        threading.Thread(target=self.finish, args=(frames, had), daemon=True).start()
            elif st == 'speaking':
                rid = self.m.current[0] if self.m.current else None
                if rid != self.echo_rid: self.echo_rid = rid; self.echo = 0.0; self.speech = 0; wake.reset()   # a new reply, a new room
                pl = self.player.play_level; r = rms(f)
                if max(wake.predict(f).values()) > 0.5:                             # the name always interrupts
                    self.speech = 0; wake.reset(); self.feed('wake')
                else:                                                               # louder than his own echo, for 320 ms
                    settling = time.time() - self.player.play_t0 < 0.6              # calibrate first, judge after
                    # judged on what we knew before this frame, and never on an estimate we do not have yet
                    over = self.echo > 0.0 and not settling and vad(f) and r > max(RMS_ON, self.echo * pl * ECHO_MARGIN)
                    if pl > 0.05 and not over:                                      # only his own voice teaches the estimate
                        ratio = r / pl; self.echo = ratio if self.echo == 0.0 else 0.9 * self.echo + 0.1 * ratio
                    self.speech = self.speech + 1 if over else 0                    # ponytail: a voice arriving inside the
                    # 0.6 s settle window still teaches the estimate, so it reads loud; the name is the door for that case
                    if self.speech >= 4: self.speech = 0; self.feed('wake')
            elif st in ('idle', 'waiting', 'thinking'):                             # the machine takes the name from all three
                if max(wake.predict(f).values()) > 0.5: wake.reset(); self.feed('wake')
    def partial(self, frames):
        try:
            t = transcribe(frames)
            if t and self.mic_open: stream.emit({'t': 'you', 'text': t, 'final': False})
        except Exception: pass
    def finish(self, frames, had_speech):
        text = ''
        try:
            if had_speech: text = transcribe(frames)
        except Exception as e:
            print('whisper failed:', e, file=sys.stderr)
            try: open(os.path.join(BRAIN, 'voice', 'failed', f'{int(time.time())}.wav'), 'wb').write(wav_bytes(frames))
            except Exception: pass
            self.act([('say_bridge', 'I could not hear that. The transcriber is down.')])
        finally:                                          # whatever happened, the machine leaves `listening`
            stem = f"note-{int(time.time() * 1000)}-voice-{slugify(text)}"
            if text: stream.emit({'t': 'you', 'text': text, 'final': True})
            self.finishing = False
            self.feed('speech_end', text=text, stem=stem)
    def housekeeping(self):
        while True:
            try:
                for name, fn in (('dnd', 'dnd'), ('meeting', 'meeting'), ('voice_on', 'voice.on')):
                    p = os.path.join(BRAIN, fn); v = os.path.exists(p)
                    if name == 'voice_on' and v and time.time() - os.path.getmtime(p) > 7200: os.remove(p); v = False
                    if v != self.flags[name]: self.flags[name] = v; self.feed('flag', name=name, value=v)
                age = time.monotonic() - self.m.since
                if self.m.state == 'thinking' and age > 5 and not self.said_working: self.said_working = True; self.act([('say_bridge', 'Working on it.')])
                if (self.m.state == 'thinking' and age > 60) or (self.m.state == 'waiting' and age > 600): self.feed('timeout')
                # nothing playing and nothing rendering is not `speaking`; a closed microphone is not `listening`
                self.idle_speak = self.idle_speak + 1 if self.m.state == 'speaking' and not self.player.busy() else 0
                self.idle_listen = self.idle_listen + 1 if self.m.state == 'listening' and not self.mic_open and not self.finishing else 0
                if self.idle_speak >= 10: self.idle_speak = 0; print('voice: speaking with nothing to play; advancing', file=sys.stderr); self.feed('sentence_done')
                if self.idle_listen >= 5: self.idle_listen = 0; print('voice: listening with the microphone shut; closing the turn', file=sys.stderr); self.feed('speech_end', text='')
            except Exception as e: print('housekeeping:', e, file=sys.stderr)
            time.sleep(1)

LOOP = None
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _cors(self): self.send_header('Access-Control-Allow-Origin', '*'); self.send_header('Access-Control-Allow-Headers', 'Content-Type')
    def do_OPTIONS(self): self.send_response(204); self._cors(); self.end_headers()
    def do_GET(self):
        if self.path.startswith('/stream'):
            self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.send_header('Cache-Control', 'no-cache'); self._cors(); self.end_headers()
            q = stream.subscribe()
            try:
                self.wfile.write(('data: ' + json.dumps(stream.last_state) + '\n\n').encode()); self.wfile.flush()
                while True:
                    try: line = q.get(timeout=15)
                    except queue.Empty: line = ': keepalive\n\n'
                    self.wfile.write(line.encode()); self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError): pass
            finally: stream.unsubscribe(q)
        elif self.path.startswith('/state'):
            self.send_response(200); self.send_header('Content-Type', 'application/json'); self._cors(); self.end_headers(); self.wfile.write(json.dumps(stream.last_state).encode())
        else: self.send_response(404); self.end_headers()
    def do_POST(self):
        n = int(self.headers.get('Content-Length') or 0); body = json.loads(self.rfile.read(n) or b'{}') if n else {}
        if self.path == '/listen': LOOP.feed('key')
        elif self.path == '/stop': LOOP.feed('stop')
        elif self.path == '/say':
            text = (body.get('text') or '').strip()
            if text:
                stem = f"note-{int(time.time() * 1000)}-typed-{slugify(text)}"; stream.emit({'t': 'you', 'text': text, 'final': True, 'typed': True})
                LOOP.feed('typed', text=text, stem=stem, voice=text.lower().endswith('in voice'))
        else: self.send_response(404); self.end_headers(); return
        self.send_response(200); self._cors(); self.end_headers()

def main():
    global LOOP
    LOOP = Loop()
    threading.Thread(target=LOOP.audio, daemon=True).start()
    threading.Thread(target=LOOP.housekeeping, daemon=True).start()
    threading.Thread(target=watch_replies, args=(LOOP.on_reply,), daemon=True).start()
    stream.emit({'t': 'state', 'state': 'idle'})
    print(f'janus voice: http://127.0.0.1:{PORT}/stream · mic {MIC} · wake {WAKE} · voice {VOICE} · vad {VAD_MODE}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()

if __name__ == '__main__': main()
