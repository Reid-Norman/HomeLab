# HomeLab

A self-hosted media server run entirely as code. 22 containers in five Docker Compose stacks are deployed with `make`, then configured through their REST APIs by Ansible, with every secret in Ansible Vault.

**📖 Documentation: [reid-norman.github.io/HomeLab](https://reid-norman.github.io/HomeLab/)**: architecture, access and security, services, operations, troubleshooting, and [architecture decision records](https://reid-norman.github.io/HomeLab/decisions/).

## Highlights

- **Infrastructure as code:** Compose provisions, 17 Ansible roles configure. `make deploy-all && make ansible-sync` rebuilds a working setup, and re-running only changes what drifted.
- **Zero open router ports:** public apps go through Cloudflare Tunnel, remote admin access through Tailscale.
- **One login with two-factor** (Authelia) in front of every admin page, failing closed. Admin ports listen on loopback only.
- **TLS everywhere** from one Let's Encrypt wildcard certificate, with HSTS and security headers on every route.
- **Secrets never touch git:** Ansible Vault, generated `.env` files, gitleaks in CI.
- **Modular:** five single-purpose stacks with one-way dependencies, and Compose profiles for optional pieces.

## Stacks

| Stack | Services |
|-------|----------|
| **docker-networking-stack** | Traefik, AdGuard Home, cloudflared *(optional `tunnel` profile)* |
| **docker-auth-stack** | Authelia |
| **docker-management-stack** | Homepage, Portainer, Watchtower, Uptime Kuma, Dozzle |
| **docker-media-stack** | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Seerr, FlareSolverr, Gluetun VPN, Recommendarr, Shelfmark, Audiobookshelf |
| **docker-automation-stack** | Semaphore, PostgreSQL |

## Quick start

```bash
make ansible-deps                                          # Ansible collections
make generate-creds STACK=all                              # credentials into Ansible Vault
docker network create --subnet=172.20.0.0/16 homelab-network
make env                                                   # render .env files and Authelia config
make deploy-all                                            # networking → auth → management → media → automation
# manual steps: Authelia 2FA, Jellyfin and Seerr wizards, Prowlarr indexers
make extract-keys                                          # app API keys into the vault
make ansible-sync                                          # configure everything through the APIs
```

Prerequisites, profiles, the manual steps and every `make` target: [Getting started](https://reid-norman.github.io/HomeLab/getting-started/).

## Repository layout

```
docker-*-stack/       one directory per stack: docker-compose.yml, .env.j2 template, .env.example
ansible/              site.yml, roles/, group_vars/all/{vars.yml, vault.yml (encrypted)}
scripts/              generate-credentials.sh, extract-api-keys.sh
docs/                 this documentation site (MkDocs Material)
.github/workflows/    validate.yml (lint, syntax, gitleaks), docs.yml (build and publish docs)
Makefile              the main interface
CLAUDE.md             project conventions for the AI coding agent
```

Built with [Claude Code](https://claude.com/claude-code) under human review: see [How this was built](https://reid-norman.github.io/HomeLab/how-it-was-built/).
