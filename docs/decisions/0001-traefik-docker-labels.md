# 0001. Traefik with Docker labels instead of Nginx Proxy Manager

**Status:** accepted · **Date:** 2026-03-06

## Context

The first reverse proxy was Nginx Proxy Manager. Each host, certificate and upstream was configured by clicking through its UI and stored in its database. That breaks the project's rules: nothing manual that can be automated, and a fresh machine should rebuild from the repo.

## Decision

Use Traefik with the Docker provider. Each service declares its own route in its compose file: `traefik.enable`, a `Host()` rule, the entrypoint and the port. Certificates come from Let's Encrypt with the Cloudflare DNS-01 challenge, so nothing has to be reachable from the internet to get one.

## Consequences

- Routing lives next to the service it belongs to and is reviewed like any other code. Removing a service removes its route.
- Traefik needs the Docker socket (read access to container metadata). It's the one ingress component trusted with it.
- On Docker Desktop for Mac, Traefik needs v3.6 or newer for Docker API version negotiation.
- Label conventions matter, and are documented in `CLAUDE.md`: for example, services in the VPN namespace carry their labels on the Gluetun container.
