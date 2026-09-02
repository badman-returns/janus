# proof/cockpit — mission control v0.5.3

Captured 2026-09-02 against the live iit-roorkee machine (ttyd 1.7.7, tmux 3.6b, Chrome).

- 00-claude-in-the-page.jpg — 0.5.2: a Claude Code session started by "+ session" runs inside the machine and renders as a live, typeable terminal tile.
- 01-grid-dark.jpg — §6: sentence-case tile headers, flat surfaces, one pill style, counts on chips, no glow/gradient anywhere; state tiles quieter than terminals.
- 02-focus-claude-dark.jpg — §3 focus mode: the tile fills the page, the tray becomes a 56px icon rail with counts; alert badge is the only accent.
- 03-split-claude-api.jpg — §3 split: shift-click a rail chip; Claude beside the api server, both live.
- 04-mobile-focus.jpg — §3 under 720px: rail runs horizontally, one terminal, dock intact.

Also verified this session, not pictured: light theme renders from the same tokens (server injects theme.json into both pages); fleet page shows the real "needs you" ring on the project holding an open gate; 12s idle with 6 live tiles produced zero websocket reconnects after the skeleton-rebuild fix.

## 0.5.4 additions
- 05-sidebar-pinned-light.jpg — sidebar replaces the tile tray: Overview / Sessions / Services / Machine / System, counts and live dots, pinned open (light theme).
- 06-mobile-rail.jpg — under 720px the sidebar is a horizontal icon rail with badges above the main area.
- (verified live, 12:02) AskUserQuestion → ask card on Waiting on you within 6s → answered "Blue" from the dashboard → Claude continued with "Operator answered from mission control: Blue" and replied Blue. No terminal touched.
