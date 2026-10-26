# 0005. One wildcard certificate, requested by one router

**Status:** accepted · **Date:** 2026-10-25

## Context

After DNS was fixed, Traefik started requesting a separate certificate for every hostname. The cert resolver had been set on the `websecure` entrypoint, and Traefik treats that as "every router asks for its own". That's one order per hostname, all racing each other and Let's Encrypt's rate limits. It also publishes every service name in public Certificate Transparency logs.

## Decision

- Request one certificate for `domain` and `*.domain`, from the Traefik dashboard router only (`tls.certresolver` plus `tls.domains`).
- Turn TLS on for the entrypoint (`http.tls=true`) without a resolver, so every other router picks the wildcard from the store.
- No `certresolver` label on any other router.

## Consequences

- One renewal, one rate-limit budget, and CT logs show only `*.domain`.
- The convention is easy to break by copying a label from a tutorial. It's called out in `CLAUDE.md` and in the troubleshooting page.
- If the dashboard router is removed, nothing requests the certificate. It's in the networking stack next to Traefik for that reason.
