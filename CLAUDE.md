# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted media infrastructure automation for a Mac Mini. Docker Compose handles container provisioning; Ansible handles post-deployment configuration via REST API calls. Secrets live in Ansible Vault, never in plaintext.

## Repository Layout

Four independent Docker Compose stacks at the repo root, each with its own `docker-compose.yml`, `.env.example`, and `.env.j2` (Ansible Jinja2 template):

- **docker-media-stack/** — Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Jellyseerr, Recyclarr, FlareSolverr, Gluetun VPN, Cloudflared, Recommendarr, LazyLibrarian, Audiobookshelf
- **docker-management-stack/** — Portainer, Watchtower, Uptime Kuma, Dozzle
- **docker-networking-stack/** — Traefik, AdGuard Home
- **docker-automation-stack/** — Semaphore (Ansible UI)

Ansible config lives in `ansible/` with roles for: env_files, qbittorrent, prowlarr, sonarr, radarr, jellyseerr, recyclarr, adguard, traefik, uptime_kuma. Main playbook is `ansible/site.yml`. Non-secret vars in `ansible/group_vars/all/vars.yml`, encrypted secrets in `ansible/group_vars/all/vault.yml`.

## Common Commands

```bash
# Deploy individual stacks
make deploy-media
make deploy-management
make deploy-networking
make deploy-automation

# Deploy all stacks (management → networking → media → automation)
make deploy-all

# Install/update Ansible collections (run once, or after changing requirements.yml)
make ansible-deps

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
- **Static IPs:** Radarr and Sonarr get static container IPs on the Docker network for stable inter-service communication.
- **Shared network:** All stacks share the `jellyfinnet` Docker network (172.20.0.0/16) so Traefik can route to any container by name.
- **Traefik labels:** Routing is declarative via Docker labels on each service — `traefik.enable=true`, `Host()` rule, entrypoint, certresolver, and loadbalancer port. VPN-namespaced services (qBittorrent, Prowlarr) get their labels on the Gluetun container.
- **Ansible post-config:** After containers are running, Ansible roles configure services by calling their REST APIs (health checks, indexer setup, download client wiring, DNS rewrites).
- **Hostname-based access:** All services accessed via `*.hightechlowlife.ca` — AdGuard provides DNS rewriting, Traefik handles reverse proxy + TLS via Let's Encrypt wildcard certs (Cloudflare DNS-01 challenge).

## Key Service Relationships

```
Prowlarr → Radarr/Sonarr  (indexer sync)
Radarr/Sonarr → qBittorrent  (download client)
Jellyseerr → Radarr/Sonarr  (media requests)
Jellyfin  (serves media library)
AdGuard Home  (DNS rewriting for *.hightechlowlife.ca)
Traefik  (reverse proxy + TLS termination)
```

## When Modifying Docker Compose Files

- All services use `restart: unless-stopped`
- Services load config from `env_file: [.env]`
- Use named volumes for persistent data (e.g., `sonarr-config:/config`)
- LinuxServer.io images expect `PUID`, `PGID`, and `TZ` environment variables
- All stacks must include the `jellyfinnet` external network
- Each compose file must have a `name:` directive matching the directory name

## Rules

- Never commit .env files or vault.yml with real values
- Always add new services to both docker-compose.yml AND the Ansible role
- All services must have a corresponding Uptime Kuma monitor in vars.yml
- New stacks must follow the existing naming convention: docker-X-stack
- Always use named volumes, never hardcoded host paths
- Secrets go in Ansible Vault, never in vars.yml
- `.env` files are generated from `.env.j2` templates via the `env_files` role

## When Modifying Ansible

- Roles target `localhost` with `connection: local` and `gather_facts: false`
- Vault file is encrypted with `ansible-vault` — use `make vault-edit` to modify
- Collections (`community.general`, `lucasheld.uptime_kuma`) are listed in `ansible/requirements.yml` — install with `make ansible-deps` (not run automatically by `ansible-sync` to avoid network hits on every run)
- The `env_files` role must always run first in `site.yml`
