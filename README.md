# HomeLab

Self-hosted media and infrastructure server running on a Mac Mini with Docker Compose and Ansible.

## Architecture

| Stack | Services |
|-------|----------|
| **docker-media-stack** | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Jellyseerr, Recyclarr, FlareSolverr, Gluetun VPN, Cloudflared, Recommendarr, LazyLibrarian, Audiobookshelf |
| **docker-management-stack** | Portainer, Watchtower, Uptime Kuma, Dozzle |
| **docker-networking-stack** | Nginx Proxy Manager, AdGuard Home |
| **docker-automation-stack** | Semaphore (Ansible UI) |

All services are accessible via `*.hightechlowlife.ca` using AdGuard DNS rewriting and Nginx Proxy Manager reverse proxy.

## Quick Start

1. Copy `.env.example` to `.env` in each stack directory (or use Ansible to generate them).
2. Create and encrypt `ansible/group_vars/all/vault.yml` with your secrets:
   ```bash
   cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml
   ansible-vault encrypt ansible/group_vars/all/vault.yml
   make vault-edit  # Fill in real values
   ```
3. Generate `.env` files from vault:
   ```bash
   make ansible-sync
   ```
4. Deploy stacks:
   ```bash
   make deploy-all
   ```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make deploy-media` | Start media stack (with VPN profile) |
| `make deploy-management` | Start management stack |
| `make deploy-networking` | Start networking stack |
| `make deploy-automation` | Start automation stack |
| `make deploy-all` | Start all stacks in order |
| `make ansible-sync` | Run Ansible playbook to configure services |
| `make vault-edit` | Edit encrypted vault secrets |

## Secrets Management

- All secrets live in `ansible/group_vars/all/vault.yml` (encrypted with Ansible Vault)
- `.env` files are generated from `.env.j2` Jinja2 templates via the `env_files` Ansible role
- `.env` files are gitignored and never committed
- `.env.example` files document required variables with placeholder values

## Networking

- All stacks share the `jellyfinnet` Docker network so Nginx Proxy Manager can route to any container by name
- AdGuard Home provides DNS rewriting: `*.hightechlowlife.ca` resolves to the Mac Mini's LAN IP
- Nginx Proxy Manager handles reverse proxy and TLS termination with a Cloudflare Origin Certificate
