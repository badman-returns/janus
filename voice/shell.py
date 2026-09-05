#!/usr/bin/env python3
"""Janus in the menu bar: a ring that follows the loop's state, ⌥Space to talk and ⌘. to stop, a
"Show Janus" window (Chrome in app mode at the front page), and the pill, a small always-on-top
window with the same orb, shown while the loop is not idle and the window is not in front.
Runs as the fleet machine's `shell` service from the fleet machine's root.

`JANUS_FRONT_PORT` overrides the mission control port /front and /pill are fetched from; without it
the port comes from this machine's entry in ~/.delivery-machine/registry.json. Set it to point the
shell at a throwaway server (testing from a checkout the fleet does not serve)."""
import json, os, subprocess, sys, threading, time, urllib.request
import rumps
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.getcwd()
def conf():
    try: return json.load(open(os.path.join(ROOT, '.delivery', 'config.json')))
    except Exception: return {}
C = conf(); V = C.get('voice', {}) or {}; PORT = int(V.get('port', 8790)); LOOP = f'http://127.0.0.1:{PORT}'
def fleet_port():
    if os.environ.get('JANUS_FRONT_PORT'): return int(os.environ['JANUS_FRONT_PORT'])
    try:
        reg = json.load(open(os.path.expanduser('~/.delivery-machine/registry.json')))
        return reg.get(C.get('project', 'fleet'), {}).get('port') or next(iter(reg.values()))['port']
    except Exception: return 5501
FRONT = f'http://localhost:{fleet_port()}/front'; PILL = f'http://localhost:{fleet_port()}/pill'
CHROME = '/Applications/Google Chrome.app'
# macOS grants Accessibility to the app that launched this process, not to python — name it in the
# message so the operator knows which row to tick in System Settings.
HOST_APP = os.environ.get('TERM_PROGRAM') or os.environ.get('__CFBundleIdentifier') or 'this terminal'

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
        self.pill = Pill(); self.state = 'offline'; self.want = None; self.hide_at = 0
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
        front = subprocess.run(['osascript', '-e', 'tell application "System Events" to get name of first application process whose frontmost is true'], capture_output=True, text=True).stdout.strip()
        if s not in ('idle', 'muted', 'offline') and 'Chrome' not in front: self.pill.show(); self.hide_at = 0
        elif s in ('idle', 'muted', 'offline'): self.hide_at = time.time() + 3
    def tick(self, _):
        """The menu bar and the pill are only ever touched from here, on the main thread. rumps'
        Timer schedules on the run loop of whatever thread starts it, so a timer armed from
        follow() would never fire at all — follow() leaves the newest state in self.want and this
        applies it. The three seconds after idle are also this clock's: once the loop goes quiet it
        sends nothing but a 15 s keepalive, so a stream-driven hide would leave the pill up long
        after there was anything to say."""
        if self.want and self.want != self.state: self.set_state(self.want)
        if self.hide_at and time.time() > self.hide_at: self.hide_at = 0; self.pill.hide()
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
        try:
            import HIServices
            from pynput import keyboard
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
