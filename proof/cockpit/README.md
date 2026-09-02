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

## 0.5.5–0.5.6 (not pictured; verified in the browser during the session)
- Indigo-on-slate visual pass: 4px surfaces, icon controls with CSS tooltips (hover "Session" → "Start a Claude session inside the machine"), sun/moon/auto theme control, flat composer with icon send; checked in both themes.
- Cockpit split into its own plugin (plugin-mc/); both dashboards restarted from the new path with --scripts and served the new tokens.
- Ledger: run-log.sh refuses done from a builder and from a verifier without fresh proof (test_run_log); dm-gate.sh writes no Gate 2 file on stale proof.

## 0.5.7
- 07-slice-story.jpg — header usage pill (ctx · 5h · $), sidebar session badge 40%, Agent runs with ledger pills, and the slice story drawer for cr18-checkin-rescheduled: status on branch, spec, ledger timeline, commits (proof and decisions below the fold).
- (verified, not pictured) gate threads on a throwaway project; dm-prune removed two merged worktrees on iit-roorkee and kept four; dm-proof CI green on DilSayCare/IIT-Roorkee-Wellness main (ca2c994) with both databases migrated.
