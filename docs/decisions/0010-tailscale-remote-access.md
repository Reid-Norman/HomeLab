# 0010. Tailscale subnet route for remote access

**Status:** accepted · **Date:** 2026-10-25

## Context

Admin pages were reachable only at home. The options for remote access:

- **Open ports on the router:** rejected; there are no inbound ports, by design.
- **Put admin pages behind Cloudflare Access on the tunnel:** this exposes admin surfaces to the internet, guarded only by one more login.
- **A private overlay network.** Tailscale is free for personal use and connects out like the tunnel.

## Decision

- **Homebrew `tailscaled` on the server.** It runs at boot as root, even before anyone logs in. The Tailscale app only runs inside a user session, and running both at once makes them fight over the same socket.
- **The server advertises its own LAN IP as a `/32` subnet route.** The public DNS-only wildcard ([ADR 0006](0006-public-dns-only-wildcard.md)) already points there, so the same URLs work at home and away, with no split DNS.
- **`--accept-dns=false`,** so Tailscale can't change the host's DNS ([ADR 0004](0004-no-desktop-vpn-on-server.md)).
- **Key expiry is off for the server only.**
- **Setup stays manual,** because it needs sudo and a browser login. The `tailscale` Ansible role only reports status, and never fails the play.

## Consequences

- No inbound ports. Only devices signed in to the tailnet can reach the server, and Authelia still guards every admin page.
- A tailnet device can reach every port the server publishes on its LAN IP (Jellyfin, DNS, torrents), the same as being at home.
- With Tailscale on at home, traffic to the server goes through Tailscale. It still connects directly over the LAN, so the only cost is encryption overhead.
- Turning key expiry off means a stolen server key stays valid until it's revoked in the admin console.
