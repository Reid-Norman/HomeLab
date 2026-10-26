# 0007. One purpose per stack, dependencies point one way

**Status:** accepted · **Date:** 2026-10-25

## Context

New services (single sign-on, a start page) had to go somewhere. The goal was stacks that are "modular and somewhat independently useful for others", so someone could take just the networking stack, or just media.

At the time, cloudflared lived in the media stack. Redeploying media dropped the public tunnel, and the media stack needed a Cloudflare account to run at all.

## Decision

Each stack has one purpose, and dependencies only point down the list: networking → auth → management → media → automation.

- **cloudflared moves to networking,** as the optional `tunnel` profile. It's ingress, like Traefik.
- **Authelia gets its own auth stack.** It's a security boundary with its own secrets and lifecycle, and it works in front of any Traefik setup.
- **Homepage goes in management, not networking.** Its widgets need every app's API keys, which shouldn't sit in the foundation stack that everything else depends on.
- **The coupling to auth is one setting.** Admin routes use `${ADMIN_MIDDLEWARES}`, rendered from `traefik_admin_middlewares`, so no stack hard-codes Authelia.
- **Optional pieces are Compose profiles.**

## Consequences

- `make deploy-all` deploys in dependency order and `make down-all` in reverse.
- The media stack runs without a Cloudflare account, and redeploying it no longer touches the tunnel.
- Every new service needs a placement decision first: which way would its dependencies point, and where would its secrets live?
