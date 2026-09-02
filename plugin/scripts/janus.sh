#!/usr/bin/env bash
# The front door. Run from anywhere: every machine on this host, pick one, land in it.
#
#   janus.sh              interactive picker
#   janus.sh <name>       open that machine directly, no picker
#   janus.sh --list       one TSV row per machine (the testable seam; also what pipes)
#
# Reads only things that already exist: the fleet registry, each project's inbox and
# ledger. Writes nothing. Opening a machine is exactly what dm.sh already does.
set -uo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG="${DM_REGISTRY:-$HOME/.delivery-machine/registry.json}"

# ---- data ------------------------------------------------------------------
# name \t dir \t alive \t waiting \t port \t ttyd \t recap
rows() {
  python3 - "$REG" <<'PY'
import json, os, subprocess, sys

reg_path = sys.argv[1]
try:
    reg = json.load(open(reg_path))
except Exception:
    sys.exit(0)

def alive(session):
    return subprocess.run(["tmux", "has-session", "-t", session],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def waiting(d):
    ib = os.path.join(d, ".delivery", "inbox")
    try:
        return sum(1 for f in os.listdir(ib)
                   if not f.startswith(("reply-", "note-", "."))
                   and os.path.isfile(os.path.join(ib, f)))
    except OSError:
        return 0

def recap(d):
    """One honest line about where this machine stopped. The ledger is the only
    place that records it; HANDOFF.md is sectioned state, not a summary."""
    try:
        with open(os.path.join(d, ".delivery", "runs.jsonl")) as f:
            last = [l for l in f if l.strip()][-1]
        r = json.loads(last)
        line = f"{r.get('agent','?').replace('dm-','')} · {r.get('slice','?')} · {r.get('status','?')}"
        note = (r.get("note") or "").strip()
        return f"{line} — {note}" if note else line
    except Exception:
        pass
    try:
        br = subprocess.run(["git", "-C", d, "branch", "--show-current"],
                            capture_output=True, text=True, timeout=3).stdout.strip()
        st = subprocess.run(["git", "-C", d, "status", "--short"],
                            capture_output=True, text=True, timeout=3).stdout.strip()
        n = len([x for x in st.split("\n") if x])
        return f"no runs yet · {br or 'detached'}" + (f", {n} changed" if n else ", clean")
    except Exception:
        return "no runs yet"

for name, v in reg.items():
    d = v.get("dir", "")
    if not os.path.isdir(d):
        print("\t".join([name, d, "0", "0", "", "", "directory is gone"]))
        continue
    print("\t".join([name, d,
                     "1" if alive(v.get("session", "")) else "0",
                     str(waiting(d)),
                     str(v.get("port") or ""), str(v.get("ttyd_port") or ""),
                     recap(d)]))
PY
}

# ---- opening ---------------------------------------------------------------
open_machine() {  # <dir>
  cd "$1" || { echo "cannot enter $1" >&2; exit 1; }
  exec bash "$PLUGIN_ROOT/scripts/dm.sh"
}

# ---- non-interactive paths -------------------------------------------------
if [ "${1:-}" = "--list" ]; then rows; exit 0; fi

if [ -n "${1:-}" ]; then
  line=$(rows | awk -F'\t' -v n="$1" '$1==n {print; exit}')
  [ -n "$line" ] || { echo "no machine named '$1'. Known:"; rows | cut -f1 | sed 's/^/  /'; exit 1; }
  open_machine "$(printf '%s' "$line" | cut -f2)"
fi

# ---- render ----------------------------------------------------------------
if [ -t 1 ]; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
  ACC=$'\e[38;5;111m'; OK=$'\e[38;5;79m'; WARN=$'\e[38;5;221m'; MUT=$'\e[38;5;245m'
else
  B=""; D=""; R=""; ACC=""; OK=""; WARN=""; MUT=""
fi

ROWS=()
while IFS= read -r l; do ROWS+=("$l"); done < <(rows)
N=${#ROWS[@]}
if [ "$N" -eq 0 ]; then
  echo "  ${B}JANUS${R}  no machines registered yet."
  echo "  ${MUT}Run /dm-init in a project, then orchestrator.sh.${R}"
  exit 0
fi

field(){ printf '%s' "${ROWS[$1]}" | cut -f"$2"; }

# widest name, so the status column lines up
W=0; for i in $(seq 0 $((N-1))); do n=$(field "$i" 1); [ ${#n} -gt $W ] && W=${#n}; done

draw() {
  local need=0 i
  for i in $(seq 0 $((N-1))); do [ "$(field "$i" 4)" != "0" ] && need=$((need+1)); done
  printf '\n  %sJANUS%s  %s%s machines · %s%s\n\n' "$B" "$R" "$MUT" "$N" \
    "$([ "$need" -gt 0 ] && printf '%s%s needs you%s' "$WARN" "$need" "$MUT" || printf 'nothing waiting')" "$R"
  for i in $(seq 0 $((N-1))); do
    local name dir up wait port recap dot mark tag
    name=$(field "$i" 1); up=$(field "$i" 3); wait=$(field "$i" 4)
    port=$(field "$i" 5); recap=$(field "$i" 7)
    [ "$up" = "1" ] && dot="${OK}●${R}" || dot="${MUT}○${R}"
    [ "$i" = "$SEL" ] && mark="${ACC}▸${R}" || mark=" "
    if [ "$wait" != "0" ]; then tag="${WARN}${wait} waiting${R}"
    elif [ "$up" = "1" ]; then tag="${MUT}running${R}"
    else tag="${MUT}stopped${R}"; fi
    printf '  %s %s%d%s  %s %-*s  %s\n' "$mark" "$D" $((i+1)) "$R" "$dot" "$W" "$name" "$tag"
    printf '       %s%s%s\n' "$MUT" "$recap" "$R"
  done
  printf '\n  %s↑↓ move · ⏎ open · d dashboard · q quit%s\n' "$MUT" "$R"
}

# no TTY to read keys from (piped, CI): print once and stop
if [ ! -t 0 ]; then SEL=-1; draw; exit 0; fi

SEL=0
cleanup(){ printf '\e[?25h'; }
trap cleanup EXIT
printf '\e[?25l'
draw
DRAWN=$((N*2+5))

while true; do
  IFS= read -rsn1 k || break
  # An arrow is ESC [ A/B and arrives in pieces. Read the rest with a window wide enough
  # to survive a slow pipe (tmux, ssh) — and never treat a lone ESC as a command, because
  # a timeout that fires early would then quit the launcher under the operator.
  if [ "$k" = $'\e' ]; then
    # -t must be a whole number: macOS ships bash 3.2, which rejects "0.4" outright and
    # then returns nothing, leaving the [ and A to be read as separate keystrokes.
    IFS= read -rsn2 -t 1 rest || rest=""
    # A cursor key is ESC [ A or ESC O A depending on whether the terminal is in
    # application mode — tmux and ssh differ. Match the final letter, not the prefix,
    # and ignore a lone ESC rather than letting an early timeout act as a command.
    case "$rest" in
      *A) k=up ;; *B) k=down ;; *) continue ;;
    esac
  fi
  case "$k" in
    up|k) SEL=$(( (SEL+N-1) % N )) ;;
    down|j) SEL=$(( (SEL+1) % N )) ;;
    ""|$'\n') cleanup; open_machine "$(field "$SEL" 2)" ;;
    d) p=$(field "$SEL" 5); [ -n "$p" ] && open "http://localhost:$p" 2>/dev/null ;;
    q) cleanup; echo; exit 0 ;;
    [1-9]) if [ "$k" -le "$N" ]; then SEL=$((k-1)); cleanup; open_machine "$(field "$SEL" 2)"; fi ;;
  esac
  printf '\e[%dA\e[J' "$DRAWN"   # rewind over what we drew, redraw in place
  draw
done
cleanup
