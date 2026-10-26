# Access and security

## Hostnames

| Service | Hostname | Service | Hostname |
|---------|----------|---------|----------|
| Homepage (start page) | `home.domain` | Portainer | `portainer.domain` |
| Jellyfin | `jellyfin.domain` | Uptime Kuma | `uptime-kuma.domain` |
| Seerr | `seerr.domain` (also `jellyseerr.domain`) | Dozzle | `dozzle.domain` |
| Sonarr | `sonarr.domain` | Semaphore | `semaphore.domain` |
| Radarr | `radarr.domain` | AdGuard Home | `adguard.domain` |
| Prowlarr | `prowlarr.domain` | Traefik dashboard | `traefik.domain` |
| qBittorrent | `qbittorrent.domain` | Authelia | `auth.domain` |
| Shelfmark | `shelfmark.domain` | Audiobookshelf | `audiobookshelf.domain` |
| Recommendarr | `recommendarr.domain` | | |

Public through Cloudflare Tunnel: `jellyfin.domain`, `requests.domain` (Seerr, behind Cloudflare Access) and `audiobooks.domain`.

## Home network DNS

The `cloudflare_dns` role keeps a public, **DNS-only** (not proxied) `*.domain` A record pointed at the server's LAN IP. Every device resolves these names with whatever DNS it already uses, so nothing on the network depends on the server being up. The tunnel hostnames are more specific records, so they still go through the tunnel.

- Check from any device: `dig +short seerr.example.com` should print the server's LAN IP.
- Give the server a DHCP reservation, so its IP doesn't change after a reboot.
- Some routers have *DNS rebinding protection*, which drops public answers that contain private IPs. Allow the domain there if `dig` returns nothing.
- Work laptops on a full-tunnel VPN usually can't reach home IPs at all; that's the VPN's policy.

AdGuard Home has the same `*.domain` rewrite for devices that use it for ad blocking. Why not make AdGuard the router's DNS: [ADR 0006](decisions/0006-public-dns-only-wildcard.md).

## Single sign-on (Authelia)

Admin pages sit behind one Authelia login with two-factor: Sonarr, Radarr, Prowlarr, qBittorrent, Shelfmark, Recommendarr, Homepage, Portainer, Uptime Kuma, Dozzle, Semaphore, AdGuard and the Traefik dashboard. One login covers all of them, because the session cookie is on the apex domain.

- **Second logins:** Sonarr, Radarr, Prowlarr and qBittorrent skip their own login behind Authelia. Portainer, Semaphore, AdGuard and Uptime Kuma keep theirs; Portainer controls the whole Docker host, so it deliberately needs both.
- **Not behind Authelia:** Jellyfin, Seerr and Audiobookshelf. Their TV and phone apps call the API directly and can't get past a login page, so they keep their own logins.
- **No bypass through ports:** admin ports are published on `127.0.0.1` only. The Mac and Ansible use `http://localhost:<port>`; other devices can't skip Authelia that way.
- **Fails closed:** if Authelia is down, admin routes return 404 instead of opening.
- **Brute-force protection:** 3 failed logins within 2 minutes lock the user for 10 minutes.
- **Logging in at `auth.domain` directly** takes you to the start page (`authelia_default_redirection_url`).

**First login:** sign in with the username and password from `make generate-creds STACK=auth`, then register a one-time-password app. Authelia has no email server, so the confirmation link is written to a file: `docker exec authelia cat /data/notification.txt`.

**Without the auth stack:** set `traefik_admin_middlewares: "traefik-auth@docker"` in `vars.yml`, then `make env`, redeploy, and `make ansible-sync`. Admin pages then use basic auth, the *arr apps go back to their own login form, and qBittorrent stops trusting Traefik's IP.

Why Authelia, and what was traded off: [ADR 0008](decisions/0008-authelia-single-sign-on.md).

## Start page (Homepage)

`https://home.domain` shows a tile per service, grouped into Media, Downloads, Network and Management, with a status dot on each and live stats for Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent and AdGuard.

- **Config is code:** tiles are committed YAML in `docker-management-stack/homepage/`, mounted read-only. Edit and refresh; no restart needed.
- **Keys stay server-side:** widget keys and logins are in `homepage.env`, loaded only by the Homepage container. Homepage calls the APIs itself, so keys never reach the browser.
- **No Docker socket:** status comes from HTTP checks, so Homepage can't read other containers' settings ([ADR 0009](decisions/0009-homepage-without-docker-socket.md)).
- **Jellyfin widget:** create an API key in Jellyfin (*Dashboard → API Keys*), save it as `vault_jellyfin_api_key` with `make vault-edit`, then `make env && make deploy-management`.

## Remote access (Tailscale)

Away from home, admin pages work over [Tailscale](https://tailscale.com). The server advertises its own LAN IP as a `/32` subnet route, so the same `https://sonarr.domain` links work anywhere, and Authelia still guards every page.

**One-time setup on the server** (sudo and a browser login):

```bash
brew install tailscale
sudo brew services start tailscale   # starts at boot, even before anyone logs in
sudo tailscale up --advertise-routes=192.168.1.100/32 --accept-dns=false
```

Then in the [admin console](https://login.tailscale.com/admin/machines), approve the route under **Edit route settings** and choose **Disable key expiry** for the server.

On each phone or laptop, install Tailscale and sign in with the same account. On a laptop, check that *Use Tailscale subnets* is on.

- Use only the Homebrew install on the server. The Tailscale app runs only while someone is logged in, and running both makes them fight over the same socket.
- `--accept-dns=false` keeps the server's DNS unchanged; certificate renewals depend on it.
- `make ansible-sync` reports whether Tailscale is logged in, the route is approved, and key expiry is off.

## Cloudflare settings

These live in the Cloudflare dashboard, not in the repo:

- **SSL/TLS → Edge Certificates:** *Always Use HTTPS*, *HSTS*, and *Minimum TLS Version* 1.2.
- **Security → WAF → Rate limiting:** limit `jellyfin.domain/Users/AuthenticateByName` (for example 5 requests a minute per IP). Jellyfin is public without Cloudflare Access because its apps can't get past a login page.
- **API token:** only *Zone → DNS → Edit* on this one zone.
