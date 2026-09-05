#!/usr/bin/env bash
# make-app.sh builds a real, double-clickable Janus.app into JANUS_APP_DIR: the plist names the
# launcher, the launcher is executable, brings the fleet machine up only when it is not already
# running, waits for the voice loop, and carries this checkout's absolute path; and the icon is a
# genuine .icns. Nothing here launches the bundle — that is a Mac with a screen, not a test.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL test_janus_app: $1"; exit 1; }

JANUS_APP_DIR="$T" bash "$REPO/voice/app/make-app.sh" > "$T/build.log" 2>&1 \
  || fail "make-app.sh exited $? — $(tail -3 "$T/build.log")"

APP="$T/Janus.app"; PLIST="$APP/Contents/Info.plist"; BIN="$APP/Contents/MacOS/janus"
[ -f "$PLIST" ] || fail "no Info.plist"
[ -f "$BIN" ]   || fail "no Contents/MacOS/janus"

# the plist: the executable name must match the file, or Finder refuses to open the bundle
key(){ plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null; }
[ "$(key CFBundleExecutable)" = janus ] || fail "CFBundleExecutable is '$(key CFBundleExecutable)', not janus"
[ "$(key CFBundleName)" = Janus ] || fail "CFBundleName is '$(key CFBundleName)'"
[ "$(key CFBundleIdentifier)" = dev.janus.frontdoor ] || fail "CFBundleIdentifier is '$(key CFBundleIdentifier)'"
[ "$(key CFBundleIconFile)" = Janus ] || fail "CFBundleIconFile is '$(key CFBundleIconFile)'"
[ "$(key LSMinimumSystemVersion)" = 13.0 ] || fail "LSMinimumSystemVersion is '$(key LSMinimumSystemVersion)'"

# the launcher: executable, valid bash, and it does the three things it exists to do
[ -x "$BIN" ] || fail "launcher is not executable"
bash -n "$BIN" || fail "launcher is not valid bash"
grep -q 'orchestrator.sh' "$BIN" || fail "launcher never starts the machine"
grep -q 'has-session' "$BIN"     || fail "launcher would start a machine that is already running"
grep -q '8790' "$BIN"            || fail "launcher never waits for the voice loop"
grep -q "$REPO" "$BIN"           || fail "launcher does not carry this checkout's path ($REPO)"
grep -q 'Google Chrome' "$BIN"   || fail "launcher never opens the window"

# the icon: a real .icns, not an empty file or a PNG with the wrong extension
ICNS="$APP/Contents/Resources/Janus.icns"
[ -s "$ICNS" ] || fail "no Janus.icns"
file "$ICNS" | grep -qi 'icon' || fail "Janus.icns is not an icns: $(file -b "$ICNS")"

# rebuildable: a second run over the top of the first must not fail or leave a nested bundle
JANUS_APP_DIR="$T" bash "$REPO/voice/app/make-app.sh" >> "$T/build.log" 2>&1 || fail "second build failed"
[ ! -e "$APP/Janus.app" ] || fail "second build nested a bundle inside the first"

echo "PASS test_janus_app"
