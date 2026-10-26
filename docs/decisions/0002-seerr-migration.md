# 0002. Replace Jellyseerr with Seerr

**Status:** accepted · **Date:** 2026-10-23

## Context

Jellyfin sign-in through Jellyseerr started failing. Jellyseerr and Overseerr had merged into Seerr, and the Jellyseerr image was frozen at `2.7.3-deprecated`. Newer Jellyfin releases rejected its sign-in request, so it would never be fixed.

## Decision

Move to `ghcr.io/seerr-team/seerr`. Copy the old volume into a new `seerr-config` volume, owned by UID 1000 because Seerr no longer runs as root. Rename the container, Ansible role and monitor to `seerr`. Keep a `jellyseerr` network alias and hostname so existing links and the Cloudflare Tunnel target keep working.

## Consequences

- Seerr imported the Jellyseerr data on first start; requests and users carried over.
- The old volume was kept for rollback, with a backup outside Docker.
- Renames now have a pattern: `uptime_kuma_retired_monitors` lists old monitor names, and Ansible deletes them.
- Seerr needs `init: true` to handle signals properly.
