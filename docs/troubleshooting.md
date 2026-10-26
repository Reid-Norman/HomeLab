# Troubleshooting

## "Not secure" or an expired certificate

**Symptom:** browsers warn on home-network hostnames; the certificate is `TRAEFIK DEFAULT CERT` or expired. Traefik logs show DNS-01 failures such as `could not find zone ... i/o timeout`.

Check what's being served:

```bash
echo | openssl s_client -connect 192.168.1.100:443 -servername seerr.example.com 2>/dev/null \
  | openssl x509 -noout -text | grep -E "Issuer:|Not After|DNS:"
```

- **DNS goes through AdGuard,** which answers the domain with the LAN IP. The resolver is pinned to `1.1.1.1:53,8.8.8.8:53` in the networking stack for this reason.
- **A desktop VPN app on the server blocks DNS.** Test with `dig +time=3 SOA example.com @1.1.1.1`; a timeout means DNS is blocked. Quit the app: Gluetun already sends torrent traffic through the VPN ([ADR 0004](decisions/0004-no-desktop-vpn-on-server.md)).
- **Each hostname has its own certificate** (in the `DNS:` line). Something added a `certresolver` to a router or the entrypoint ([ADR 0005](decisions/0005-one-wildcard-certificate.md)).

## A hostname doesn't resolve

- `dig +short seerr.example.com` should return the server's LAN IP. If it doesn't, check the `*` record in Cloudflare is *DNS only*, then run `make ansible-sync`.
- macOS caches failures. Flush with `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.
- Routers with DNS rebinding protection drop answers with private IPs: allow the domain there.

## The Authelia login fails

- The username is `admin` (or `vault_authelia_user`), not your email.
- Three failures in 2 minutes lock the user for 10 minutes. Check with `docker logs authelia | grep -i banned`.
- If the password is lost: [reset it](operations.md#reset-the-authelia-password).
- Admin pages return 404: Authelia isn't running (`make deploy-auth`). That's the fail-closed behaviour.

## Torrents have no incoming connections

qBittorrent's listening port must match the port PIA forwards, which changes on reconnect. Compare `docker exec vpn cat /tmp/gluetun/forwarded_port` with qBittorrent's *Settings → Connection → Listening port*.

- **Empty file:** Gluetun has no forwarded port. PIA streaming-optimized servers don't support forwarding, so use regular servers with `VPN_PORT_FORWARDING=on`. If Gluetun's log shows `bad signature`, recreate the container: `docker compose -f docker-media-stack/docker-compose.yml up -d --force-recreate vpn`.
- **Different port:** run `make ansible-sync`, which re-syncs it. Gluetun normally pushes it automatically ([ADR 0003](decisions/0003-qbittorrent-port-sync-and-auth.md)).

## Remote access over Tailscale doesn't work

Run `make ansible-sync` and read the `tailscale` role's message. It says whether Tailscale is logged out, the route is missing or unapproved, or key expiry is on. On the phone, check Tailscale is connected and, on laptops, that *Use Tailscale subnets* is on.

## Docker API version errors

Docker Desktop negotiates API versions differently from Linux. Traefik needs v3.6 or newer; Watchtower needs `DOCKER_API_VERSION=1.44` (already set).

## A service can't reach another

1. Are both on `homelab-network`?
2. Is the target in the VPN namespace? Then use the hostname `vpn`, not its container name.
3. Is the port right? Images change defaults (Dozzle 10+ listens on 8080).

## An Ansible health check times out

The container isn't running or hasn't finished starting. Check `docker compose ps` in its stack. Retries cover 2 minutes of normal startup.

## Passwords with `$` break

Compose treats `$` as interpolation. Templates escape it with `| replace('$', '$$')`.

## A role fails with no useful error

`no_log: true` hides errors from credential-handling tasks too. Write a throwaway playbook that prints only the HTTP status, or temporarily set `no_log: false` locally. Never commit that.
