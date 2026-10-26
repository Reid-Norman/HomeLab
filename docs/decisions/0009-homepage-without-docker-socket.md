# 0009. Homepage without the Docker socket, with its own env file

**Status:** accepted · **Date:** 2026-10-25

## Context

The start page shows live stats, so it needs the Sonarr, Radarr and Prowlarr API keys, the qBittorrent and AdGuard logins, and a Jellyfin key. Homepage can also discover services from Docker labels, which would make each stack advertise its own tiles. That needs the Docker socket, or a socket proxy.

## Decision

- **No Docker socket or socket proxy.** Even a read-only proxy allows container inspection, and inspection returns every container's environment, which includes secrets. Status dots come from HTTP `siteMonitor` checks to each container instead.
- **Tiles are committed YAML,** mounted read-only, with `{{HOMEPAGE_VAR_*}}` placeholders for the domain and keys.
- **Keys go in `homepage.env`, loaded only by the Homepage container.** They aren't in the management stack's shared `.env`, which Portainer, Watchtower, Uptime Kuma and Dozzle also load.
- **Homepage sits behind Authelia** with no published port. Its host check allows only `home.domain` and `homepage:3000` (for Uptime Kuma).

## Consequences

- A compromised Homepage exposes its own widget keys, not the rest of the server.
- Homepage calls the APIs server-side, so keys never reach the browser.
- New services need a tile added by hand. That's in the "add a service" runbook and in `CLAUDE.md`.
- Services that aren't deployed show a red dot instead of disappearing.
