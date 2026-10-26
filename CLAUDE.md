# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted media infrastructure automation. Docker Compose handles container provisioning; Ansible handles post-deployment configuration via REST API calls. Secrets live in Ansible Vault, never in plaintext. Developed on macOS with Docker Desktop but adaptable to any Docker host.

## Repository Layout

Five independent Docker Compose stacks at the repo root, each with its own `docker-compose.yml`, `.env.example`, and `.env.j2` (Ansible Jinja2 template):

- **docker-networking-stack/** — Traefik, AdGuard Home, Cloudflared (optional `tunnel` profile)
- **docker-auth-stack/** — Authelia (single sign-on with 2FA for admin pages; config rendered from `authelia/*.j2`)
- **docker-management-stack/** — Homepage (start page at `home.domain`; tiles in `homepage/*.yaml`), Portainer, Watchtower, Uptime Kuma, Dozzle
- **docker-media-stack/** — Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Seerr, Recyclarr, FlareSolverr, Gluetun VPN, Recommendarr, Shelfmark, Audiobookshelf
- **docker-automation-stack/** — Semaphore (Ansible UI)

Ansible config lives in `ansible/` with roles for: env_files, cloudflare_tunnel, cloudflare_dns, qbittorrent, prowlarr, sonarr, radarr, jellyfin, seerr, recyclarr, adguard, traefik, authelia, homepage, uptime_kuma, semaphore. Main playbook is `ansible/site.yml`. Non-secret vars in `ansible/group_vars/all/vars.yml`, encrypted secrets in `ansible/group_vars/all/vault.yml`.

## Common Commands

```bash
# Deploy individual stacks
make deploy-media          # Movies & TV only
make deploy-audiobooks     # Audiobooks only
make deploy-media-full     # All media services
make deploy-management
make deploy-networking
make deploy-auth
make deploy-automation

# Deploy all stacks (networking → auth → management → media → automation)
make deploy-all

# Install/update Ansible collections (run once, or after changing requirements.yml)
make ansible-deps

# Render .env files + Authelia config only (no API calls) — run before deploying changed stacks
make env

# Run Ansible configuration playbook
make ansible-sync

# Edit encrypted vault secrets
make vault-edit

# Direct docker compose (from repo root)
cd docker-media-stack && docker compose up -d
```

## Secrets Convention

- **Single source of truth**: `ansible/group_vars/all/vault.yml` (encrypted with ansible-vault)
- **`.env` files are generated**, never manually edited — the `env_files` Ansible role renders `.env.j2` templates using vault variables
- **`.env.example`** files are committed with placeholder values for documentation
- **`vault.yml.example`** is committed with placeholder values; real `vault.yml` is gitignored
- **GitHub Secrets** only stores the vault password (for CI/CD runner to decrypt)

## Architecture Patterns

- **VPN namespace:** Services needing VPN (qBittorrent, Prowlarr, FlareSolverr) use `network_mode: "service:vpn"` — their ports are exposed via the Gluetun container, not directly.
- **Static IPs:** Radarr (`.200`) and Sonarr (`.201`) get static container IPs for stable inter-service communication. Traefik (`.202`) has one so qBittorrent can trust only it (requests that passed Authelia). Never whitelist the whole subnet anywhere: host/LAN traffic arrives from the gateway `172.20.0.1`.
- **Single sign-on:** admin routers carry `traefik.http.routers.<name>.middlewares=${ADMIN_MIDDLEWARES}` (from `traefik_admin_middlewares` in vars.yml, default `authelia@docker`; `traefik-auth@docker` is the basic-auth fallback without the auth stack). Jellyfin, Seerr and Audiobookshelf stay off it because their apps call the API directly. Admin ports are published on `127.0.0.1` only so the LAN can't bypass Authelia.
- **Shared network:** All stacks share the `homelab-network` Docker network (172.20.0.0/16) so Traefik can route to any container by name.
- **Traefik labels:** Routing is declarative via Docker labels on each service — `traefik.enable=true`, `Host()` rule, `websecure` entrypoint, and loadbalancer port. No `certresolver` label on routers or the entrypoint (either makes Traefik issue a cert per router). The `traefik-dashboard` router alone requests the `domain` + `*.domain` wildcard, and `websecure` has `http.tls=true` so all routers reuse it. VPN-namespaced services (qBittorrent, Prowlarr) get their labels on the Gluetun container.
- **Ansible post-config:** After containers are running, Ansible roles configure services by calling their REST APIs (health checks, indexer setup, download client wiring, DNS rewrites).
- **Stack layout:** one purpose per stack, and dependencies only point down (networking → management → media → automation). Networking depends on no other stack. Optional pieces are Compose profiles so each stack is reusable on its own. Before adding a service, decide its stack by dependency direction and where its secrets would end up.
- **Security headers:** the `security-headers` middleware (HSTS, nosniff, referrer policy) is defined on the Traefik container and applied to every route through the `websecure` entrypoint. Don't add it per router.
- **Hostname-based access:** All services accessed via `*.domain` — AdGuard provides DNS rewriting to the server's LAN IP, Traefik handles reverse proxy + TLS via one Let's Encrypt wildcard cert (Cloudflare DNS-01 challenge). Only `jellyfin`, `requests` (Seerr) and `audiobooks` are public, via Cloudflare Tunnel.

## Key Service Relationships

```
Prowlarr → Radarr/Sonarr  (indexer sync)
Radarr/Sonarr → qBittorrent  (download client)
Seerr → Radarr/Sonarr  (media requests; successor to Jellyseerr)
Jellyfin  (serves media library)
Shelfmark → Prowlarr  (audiobook indexer search)
Shelfmark → qBittorrent  (audiobook download client)
Audiobookshelf  (serves audiobook library)
AdGuard Home  (DNS rewriting for *.domain → server LAN IP)
Traefik  (reverse proxy + TLS termination)
```

## When Modifying Docker Compose Files

- All services use `restart: unless-stopped`
- Services load config from `env_file: [.env]`. Exception: Homepage loads only `homepage.env` (its widget API keys/logins), so the rest of the management stack never gets them
- Use named volumes for persistent data (e.g., `sonarr-config:/config`)
- LinuxServer.io images expect `PUID`, `PGID`, and `TZ` environment variables
- All stacks must include the `homelab-network` external network
- Each compose file must have a `name:` directive matching the directory name

## Rules

- Never commit .env files or vault.yml with real values
- Always add new services to both docker-compose.yml AND the Ansible role
- All services must have a corresponding Uptime Kuma monitor in vars.yml, and a tile in `docker-management-stack/homepage/services.yaml` (`siteMonitor` uses the container hostname, `href` the `https://<name>.{{HOMEPAGE_VAR_DOMAIN}}` URL)
- New stacks must follow the existing naming convention: docker-X-stack
- Always use named volumes, never hardcoded host paths. Exception: read-only config files rendered by Ansible into the stack directory (Authelia's `configuration.yml`/`users_database.yml`), mounted with a relative path and gitignored
- Secrets go in Ansible Vault, never in vars.yml
- `.env` files are generated from `.env.j2` templates via the `env_files` role

## When Modifying Ansible

- Roles target `localhost` with `connection: local` and `gather_facts: false`
- **Ansible runs on the host, not inside Docker** — role API calls must use `localhost` with the host-mapped port (e.g., `http://localhost:8096` for Jellyfin, `http://localhost:3010` for Semaphore), never container hostnames like `http://jellyfin:8096`
- Renamed/removed services: add the old monitor name to `uptime_kuma_retired_monitors` in vars.yml so the uptime_kuma role deletes it
- Uptime Kuma monitors run *inside* Docker and should use container hostnames (e.g., `http://jellyfin:8096`) — the opposite of Ansible roles
- Vault file is encrypted with `ansible-vault` — use `make vault-edit` to modify
- Collections (`community.general`, `lucasheld.uptime_kuma`) are listed in `ansible/requirements.yml` — install with `make ansible-deps` (not run automatically by `ansible-sync` to avoid network hits on every run)
- The `env_files` role must always run first in `site.yml`
