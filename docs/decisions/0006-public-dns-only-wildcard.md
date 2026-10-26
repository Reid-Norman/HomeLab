# 0006. Public DNS-only wildcard record instead of router DNS

**Status:** accepted · **Date:** 2026-10-25

## Context

`seerr.domain` didn't open on the home network. The router hands out public resolvers (1.1.1.1, 8.8.8.8), so only devices manually set to AdGuard ever saw its `*.domain` rewrite.

The textbook fix, making AdGuard the router's DNS, was rejected:

- the whole household's internet would depend on the Mac mini being up;
- work laptops on corporate VPNs broke when their DNS went through AdGuard.

## Decision

Publish a public Cloudflare record, `*.domain` A → the server's LAN IP, *DNS only* (not proxied). The `cloudflare_dns` Ansible role keeps it in place. The tunnel hostnames are more specific records, so they still win.

## Consequences

- Every device resolves the names with the DNS it already uses, and nothing depends on the server for DNS.
- A private IP is visible in public DNS. It isn't reachable from outside, but it does show the domain has a home network behind it.
- Routers with DNS rebinding protection drop answers that contain private IPs and need an exception.
- The same record makes remote access simple: Tailscale only has to route that IP ([ADR 0010](0010-tailscale-remote-access.md)).
- AdGuard's rewrite stays for devices that use it for ad blocking, and it gives the same answer.
