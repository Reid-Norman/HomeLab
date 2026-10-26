# 0003. Sync qBittorrent's port from Gluetun; narrow its login bypass

**Status:** accepted · **Date:** 2026-10-25

## Context

PIA forwards one inbound port to the VPN, and the number changes when the tunnel reconnects. qBittorrent must listen on that exact port, or peers can't connect in. Fixing it by hand after every reconnect didn't last.

Gluetun can run a command whenever it gets a new port, but that command has no qBittorrent credentials. The obvious shortcut is to trust the Docker subnet. On Docker Desktop, though, traffic from the Mac and from every LAN device reaches containers from the gateway `172.20.0.1`. Whitelisting `172.20.0.0/16` would let the whole home network skip qBittorrent's login.

## Decision

- Gluetun's `VPN_PORT_FORWARDING_UP_COMMAND` posts the new port to `http://127.0.0.1:5080/api/v2/app/setPreferences`.
- qBittorrent's **bypass authentication for localhost** is on. "Localhost" there is the VPN container's network namespace, shared only by Gluetun, qBittorrent, Prowlarr and FlareSolverr.
- The subnet whitelist stays off. With Authelia in front, the only exception is Traefik's static IP, `172.20.0.202/32` ([ADR 0008](0008-authelia-single-sign-on.md)).
- The `qbittorrent` Ansible role re-syncs the port as a backstop on every run.

## Consequences

- The port follows reconnects without anyone touching it.
- Anything that can run code inside the VPN namespace can drive qBittorrent. That's only the four containers that share it.
- The rule "never whitelist the subnet" is recorded in `CLAUDE.md`, because the subnet looks safe and isn't.
- If PIA's port request fails outright (for example a `bad signature` error), the sync has nothing to apply. Recreating the VPN container fixes it.
