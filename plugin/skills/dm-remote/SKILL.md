---
name: dm-remote
description: Set up remote access to mission control (phone/anywhere) and push notifications. Use when the user asks for remote access, phone notifications, "see the dashboard from my phone", or ntfy/Tailscale/domain setup for the delivery machine.
---

# dm-remote — stage 2

## Push notifications (ntfy — 5 minutes)
1. Pick a hard-to-guess topic, e.g. `dm-<project>-<random6>`. Set it as `ntfy_topic` in `.delivery/config.json`.
2. Operator installs the ntfy app (iOS/Android) and subscribes to that topic.
3. Done — the /dm loop already calls `scripts/notify.sh` at every gate. Test: `bash "$DM_PLUGIN/scripts/notify.sh" "test from the machine"`.
Topic names are the only auth — treat the topic like a password; messages carry no clinical or secret content (gate titles only).

## Same network
Phone browses `http://<laptop-ip>:<port>` — nothing to set up.

## Anywhere, private (Tailscale — recommended first)
1. Install Tailscale on Mac + phone, same tailnet.
2. `tailscale serve --bg <port>` → HTTPS URL reachable from the phone anywhere.

## Anywhere, real domain (Cloudflare Tunnel + Access)
1. Domain on Cloudflare. `brew install cloudflared`; `cloudflared tunnel login`; create a tunnel; route `mc.<domain>` → `http://localhost:<port>`; run cloudflared as a service (`cloudflared service install`).
2. **Mandatory**: Cloudflare Access application on `mc.<domain>` restricted to the operator's email (Google login). Never expose mission control unauthenticated — it shows code and, later, accepts approvals.
3. Laptop must be awake (`caffeinate -s` in a tmux window, or Energy Saver settings).
