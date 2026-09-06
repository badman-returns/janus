#!/usr/bin/env bash
# The pill's visibility is a rule over the current state, not a transition: it is up whenever the
# loop is doing something and the Janus window is not the frontmost thing on screen. The Janus
# window is Chrome showing the front page's own <title>; when no title can be read (no
# Accessibility) any Chrome window counts as Janus's, which is the check the shell had before.
# rumps, AppKit/objc and pynput are stubbed so this runs without voice/.venv and without a menu bar.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; VOICE="$HERE/../../voice"
fail(){ echo "FAIL test_pill_rule: $1"; exit 1; }
VOICE="$VOICE" python3 - <<'PY' || fail "rule assertions failed (above)"
import os, sys, types
for m in ('rumps', 'AppKit', 'objc', 'WebKit', 'Foundation', 'pynput'):
    sys.modules.setdefault(m, types.ModuleType(m))
sys.modules['rumps'].App = type('App', (), {})                    # rumps.App is a base class and
sys.modules['rumps'].clicked = lambda *a, **k: (lambda f: f)      # rumps.clicked a decorator, both
sys.modules['rumps'].Timer = lambda *a, **k: None                 # used while the class body runs
sys.path.insert(0, os.environ['VOICE'])
import shell
T = shell.TITLE
assert T, 'no front page <title> and no fallback'
cases = [                                                         # state, front app, front window title
    ('idle',      'Finder',        None,                          False, 'idle hides it'),
    ('listening', 'Finder',        'Untitled',                    True,  'listening behind another app shows it'),
    ('listening', 'Google Chrome', T + ' - Someone (example.ai)',  False, 'the Janus window in front hides it'),
    ('listening', 'Google Chrome', 'Inbox (3) - Gmail',           True,  'another Chrome window does not hide it'),
    ('listening', 'Google Chrome', None,                          False, 'no readable title falls back to the app name'),
    ('offline',   'Finder',        None,                          False, 'offline hides it'),
]
for state, app, title, want, why in cases:
    got = shell.pill_visible(state, app, title)
    assert got is want, f'{why}: pill_visible({state!r}, {app!r}, {title!r}) = {got}, wanted {want}'
print(f'ok: {len(cases)} cases against title {T!r}')
PY
echo "PASS test_pill_rule"
