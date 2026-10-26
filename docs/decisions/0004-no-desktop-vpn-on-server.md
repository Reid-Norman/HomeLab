# 0004. No desktop VPN app on the server

**Status:** accepted · **Date:** 2026-10-25

## Context

The wildcard certificate expired and every home-network hostname showed "not secure". AdGuard stopped resolving too. Traefik's log showed DNS-01 renewals timing out against Cloudflare.

The cause wasn't Traefik. The PIA desktop app was running on the Mac, and its DNS leak protection blocked all DNS except PIA's own resolver. That applied to the host and to every Docker container, so Traefik couldn't reach Cloudflare's API to renew, and AdGuard couldn't reach its upstreams.

## Decision

Don't run a desktop VPN on the server. Gluetun already confines torrent traffic to the VPN inside Docker, so the desktop app added nothing for this host. Also:

- AdGuard's upstreams are DNS-over-HTTPS by IP (`https://1.1.1.1/dns-query`, `https://9.9.9.9/dns-query`), which needs no bootstrap DNS and survives port 53 being blocked.
- Traefik's DNS-01 resolvers are pinned to public servers.

## Consequences

- With DNS working again, AdGuard recovered at once and the certificate was reissued (after the fix in [ADR 0005](0005-one-wildcard-certificate.md)).
- The troubleshooting page has a one-line test for this failure: `dig +time=3 SOA <domain> @1.1.1.1`.
- Anything that changes host DNS is a risk for renewals, so Tailscale runs with `--accept-dns=false` ([ADR 0010](0010-tailscale-remote-access.md)).
