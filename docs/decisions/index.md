# Architecture decision records

Short records of the decisions that aren't obvious from the code: the context, what was decided, and what it costs. They're numbered in the order they were made and are never rewritten; a changed decision gets a new record that supersedes the old one.

| ADR | Decision | Date |
|-----|----------|------|
| [0001](0001-traefik-docker-labels.md) | Traefik with Docker labels instead of Nginx Proxy Manager | 2026-03-06 |
| [0002](0002-seerr-migration.md) | Replace Jellyseerr with Seerr | 2026-10-23 |
| [0003](0003-qbittorrent-port-sync-and-auth.md) | Sync qBittorrent's port from Gluetun; narrow its login bypass | 2026-10-25 |
| [0004](0004-no-desktop-vpn-on-server.md) | No desktop VPN app on the server | 2026-10-25 |
| [0005](0005-one-wildcard-certificate.md) | One wildcard certificate, requested by one router | 2026-10-25 |
| [0006](0006-public-dns-only-wildcard.md) | Public DNS-only wildcard record instead of router DNS | 2026-10-25 |
| [0007](0007-stack-layout.md) | One purpose per stack, dependencies point one way | 2026-10-25 |
| [0008](0008-authelia-single-sign-on.md) | Authelia for single sign-on on admin pages | 2026-10-25 |
| [0009](0009-homepage-without-docker-socket.md) | Homepage without the Docker socket, with its own env file | 2026-10-25 |
| [0010](0010-tailscale-remote-access.md) | Tailscale subnet route for remote access | 2026-10-25 |
| [0011](0011-security-scanning.md) | Scan compose hardening on every push, images weekly | 2026-10-27 |
| [0012](0012-family-requests-through-moonfin.md) | Family requests inside the Moonfin app; Seerr off the internet | 2026-10-27 |
