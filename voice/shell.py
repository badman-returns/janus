#!/usr/bin/env python3
"""Janus in the menu bar: a ring that follows the loop's state, ⌥Space to talk and ⌘. to stop, a
"Show Janus" window (Chrome in app mode at the front page), and the pill, a small always-on-top
window with the same orb, shown while the loop is not idle and the window is not in front.
Runs as the fleet machine's `shell` service from the fleet machine's root.

`JANUS_FRONT_PORT` overrides the mission control port /front and /pill are fetched from; without it
the port comes from this machine's entry in ~/.delivery-machine/registry.json. Set it to point the
shell at a throwaway server (testing from a checkout the fleet does not serve)."""
import json, os, re, subprocess, sys, threading, time, urllib.request
import rumps
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.getcwd()
def conf():
    try: return json.load(open(os.path.join(ROOT, '.delivery', 'config.json')))
    except Exception: return {}
C = conf(); V = C.get('voice', {}) or {}; PORT = int(V.get('port', 8790)); LOOP = f'http://127.0.0.1:{PORT}'
def fleet_port():
    try:
        if os.environ.get('JANUS_FRONT_PORT'): return int(os.environ['JANUS_FRONT_PORT'])   # in the try: a
        reg = json.load(open(os.path.expanduser('~/.delivery-machine/registry.json')))      # junk value falls back
        return reg.get(C.get('project', 'fleet'), {}).get('port') or next(iter(reg.values()))['port']
    except Exception: return 5501
FRONT = f'http://localhost:{fleet_port()}/front'; PILL = f'http://localhost:{fleet_port()}/pill'
CHROME = '/Applications/Google Chrome.app'
# macOS grants Accessibility to the app that launched this process, not to python — name it in the
# message so the operator knows which row to tick in System Settings.
HOST_APP = os.environ.get('TERM_PROGRAM') or os.environ.get('__CFBundleIdentifier') or 'this terminal'
QUIET = ('idle', 'muted', 'offline')          # the states the pill has nothing to say about
def front_title():
    """The app window's title is the front page's own <title>, so read it there rather than
    hardcode it; Chrome appends " - <profile>" to it when the profile has a name."""
    try: return re.search(r'<title>(.*?)</title>', open(os.path.join(HERE, '..', 'plugin-mc', 'mission-control', 'front.html')).read()).group(1)
    except Exception: return 'Janus'
TITLE = front_title()
# Chrome's own scripting cannot see an app-mode window at all ("window 1 ... Invalid index"), so the
# title comes from System Events, which can. It has to be AXFocusedWindow and not `front window`:
# Chrome keeps unnamed AXUnknown windows in its window list and one of them is often window 1, so
# `name of front window` comes back empty while a named window has the focus. `front window` stays
# as the fallback, and no window at all is not an error here, just no title.
FRONT_SCRIPT = '''tell application "System Events"
  tell (first application process whose frontmost is true)
    set a to name
    set t to ""
    try
      set t to name of (value of attribute "AXFocusedWindow")
    end try
    if t is missing value then set t to ""
    if t is "" then
      try
        set t to name of front window
      end try
    end if
    if t is missing value then set t to ""
  end tell
end tell
return a & linefeed & t'''
_front = None; _asked = 0.0

def frontmost():
    """(app name, focused window title) of the frontmost app, from a cache a daemon thread refreshes
    at most once a second — that osascript measures 0.3-0.5 s here and tick() runs on the main
    thread, where waiting for it would stutter the menu bar. None until the first answer lands; the
    title is None when the app has no window or its name cannot be read."""
    global _asked
    if time.time() - _asked > 1: _asked = time.time(); threading.Thread(target=_look, daemon=True).start()
    return _front

def _look():
    global _front
    app, title = '', None
    try:
        out = subprocess.run(['osascript', '-e', FRONT_SCRIPT], capture_output=True, text=True, timeout=5)
        if out.returncode == 0:
            got = out.stdout.split('\n')
            app = got[0].strip(); title = (got[1].strip() if len(got) > 1 else '') or None
    except Exception: pass
    _front = (app, title)   # one assignment, so a reader gets the old pair or the new one

def pill_visible(state, front_app, front_title):
    """The pill is up whenever the loop is doing something and the Janus window is not the frontmost
    thing on screen — a rule over the current state, not a transition, so refocusing the window
    mid-utterance dismisses it. front_title is None when no title could be read (no Accessibility,
    osascript error): then any Chrome window counts as Janus's, the app-name check we had before."""
    if state in QUIET: return False
    if 'Chrome' not in front_app: return True
    if front_title is None: return False
    return not (front_title == TITLE or front_title.startswith(TITLE + ' - '))

def post(path):
    try: urllib.request.urlopen(urllib.request.Request(LOOP + path, data=b'{}', headers={'Content-Type': 'application/json'}), timeout=2)
    except Exception as e: print('loop unreachable:', e, file=sys.stderr)

class Pill:
    """A borderless window at status level showing pill.html; PyObjC, created lazily on the main thread."""
    def __init__(self): self.win = None
    def make(self):
        from AppKit import NSWindow, NSScreen, NSStatusWindowLevel, NSWindowStyleMaskBorderless, NSBackingStoreBuffered, NSMakeRect
        from WebKit import WKWebView
        from Foundation import NSURL, NSURLRequest
        w, h = 340, 64; sf = NSScreen.mainScreen().visibleFrame()
        rect = NSMakeRect(sf.origin.x + sf.size.width - w - 14, sf.origin.y + sf.size.height - h - 8, w, h)
        self.win = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(rect, NSWindowStyleMaskBorderless, NSBackingStoreBuffered, False)
        self.win.setLevel_(NSStatusWindowLevel); self.win.setOpaque_(False); self.win.setHasShadow_(True); self.win.setIgnoresMouseEvents_(False)
        view = WKWebView.alloc().initWithFrame_(NSMakeRect(0, 0, w, h)); view.loadRequest_(NSURLRequest.requestWithURL_(NSURL.URLWithString_(PILL)))
        self.win.setContentView_(view)
    def show(self):
        if self.win is None: self.make()
        self.win.orderFrontRegardless()
    def hide(self):
        if self.win is not None: self.win.orderOut_(None)

class Shell(rumps.App):
    def __init__(self):
        super().__init__('Janus', icon=os.path.join(HERE, 'icons', 'offline.png'), template=True, quit_button=None)
        self.menu = ['Show Janus', 'Talk (⌥ Space)', 'Stop (⌘ .)', None, 'Do not disturb', 'Quit']
        self.pill = Pill(); self.state = 'offline'; self.want = None; self.shown = False; self.hide_at = 0
        rumps.Timer(self.tick, 0.2).start()   # the only thing that touches the menu bar and the pill
        threading.Thread(target=self.follow, daemon=True).start()
        threading.Thread(target=self.hotkeys, daemon=True).start()
    @rumps.clicked('Show Janus')
    def show(self, _=None):
        if os.path.isdir(CHROME): subprocess.Popen(['open', '-na', CHROME, '--args', f'--app={FRONT}', '--window-size=1280,820'])
        else: subprocess.Popen(['open', FRONT])
    @rumps.clicked('Talk (⌥ Space)')
    def talk(self, _=None): post('/listen')
    @rumps.clicked('Stop (⌘ .)')
    def stop(self, _=None): post('/stop')
    @rumps.clicked('Do not disturb')
    def dnd(self, sender):
        p = os.path.expanduser('~/.brain/dnd')
        if os.path.exists(p): os.remove(p); sender.state = 0
        else: open(p, 'w').close(); sender.state = 1
    @rumps.clicked('Quit')
    def quit(self, _=None): rumps.quit_application()
    def set_state(self, s):
        self.state = s; self.icon = os.path.join(HERE, 'icons', f'{s}.png')
    def tick(self, _):
        """The menu bar and the pill are only ever touched from here, on the main thread. rumps'
        Timer schedules on the run loop of whatever thread starts it, so a timer armed from
        follow() would never fire at all — follow() leaves the newest state in self.want and this
        applies it. The three seconds after idle are also this clock's: once the loop goes quiet it
        sends nothing but a 15 s keepalive, so a stream-driven hide would leave the pill up long
        after there was anything to say."""
        if self.want and self.want != self.state: self.set_state(self.want)
        # The rule, every tick. The desk is only looked at when the state alone could show the pill,
        # so a quiet loop costs no osascript at all; before the first answer there is nothing to go on.
        look = frontmost() if self.state not in QUIET else None
        vis = bool(look) and pill_visible(self.state, *look)
        if vis:
            self.hide_at = 0
            if not self.shown: self.pill.show(); self.shown = True
        elif self.shown:
            if self.state in QUIET:                       # let the operator see the final state
                self.hide_at = self.hide_at or time.time() + 3
                if time.time() < self.hide_at: return
            self.pill.hide(); self.shown = False; self.hide_at = 0
    def follow(self):
        while True:
            try:
                with urllib.request.urlopen(LOOP + '/stream', timeout=None) as r:
                    for raw in r:
                        line = raw.decode().strip()
                        if not line.startswith('data: '): continue
                        ev = json.loads(line[6:])
                        if ev.get('t') == 'state': self.want = ev['state']
            except Exception:
                self.want = 'offline'; time.sleep(3)
    def hotkeys(self):
        try: import HIServices
        except Exception as e: print('hotkey: HIServices missing', e, file=sys.stderr); return
        try: from pynput import keyboard
        except Exception as e: print('hotkey: pynput missing', e, file=sys.stderr); return
        # Without Accessibility the event tap is simply never created — pynput logs a warning and its
        # thread returns, so ask macOS first or the shell would claim a hotkey it does not have.
        if not HIServices.AXIsProcessTrusted():
            print(f'hotkey: needs Accessibility for {HOST_APP}', flush=True); return
        combo = V.get('hotkey', 'alt+space').replace('alt', '<alt>').replace('space', '<space>').replace('cmd', '<cmd>')
        try:
            with keyboard.GlobalHotKeys({combo: lambda: post('/listen'), '<cmd>+.': lambda: post('/stop')}) as h:
                print('hotkey: armed', flush=True); h.join()
        except Exception as e: print(f'hotkey: needs Accessibility for {HOST_APP} ({e})', flush=True)

if __name__ == '__main__': Shell().run()
