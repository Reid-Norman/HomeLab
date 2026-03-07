# HomeLab

Self-hosted media and infrastructure automation for a Mac Mini. Docker Compose provisions containers; Ansible configures services via their REST APIs. All secrets live in Ansible Vault — nothing is manually configured that can be automated.

## Design Principles

- **Maximize automation, minimize interaction** — the challenge is automating as much as possible. Human input is only required where unavoidable (initial VPN credentials, Cloudflare tokens, Jellyfin setup wizard). Everything else is scripted via `make` targets and Ansible API calls.
- **Reproducibility** — a fresh Mac Mini should reach full functionality from `make deploy-all && make ansible-sync`.
- **Modularity** — services are grouped by purpose (media streaming, audiobooks, management, networking). Deploy only what you need via Docker Compose profiles and selective `make` targets. Not everyone wants audiobooks; not everyone needs Recommendarr.
- **Secrets as code** — all credentials live in Ansible Vault. `.env` files are generated artifacts, never edited by hand.
- **Idempotency** — every command is safe to re-run. `make ansible-sync` only changes what's needed.
- **Declarative infrastructure** — Docker labels define routing, Ansible vars define service config, vault defines secrets.

## Architecture

### Stacks

| Stack | Services | Purpose |
|-------|----------|---------|
| **docker-media-stack** | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Jellyseerr, Recyclarr, FlareSolverr, Gluetun VPN, Cloudflared, Recommendarr, LazyLibrarian, Audiobookshelf | Media acquisition, streaming, and audiobooks |
| **docker-management-stack** | Portainer, Watchtower, Uptime Kuma, Dozzle | Container management, monitoring, and auto-updates |
| **docker-networking-stack** | Traefik, AdGuard Home | Reverse proxy, TLS termination, DNS rewriting |
| **docker-automation-stack** | Semaphore | Ansible UI for running playbooks from a browser |

### Service Relationships

```
Prowlarr ──→ Radarr/Sonarr     (indexer sync — Prowlarr pushes indexers to both)
Radarr/Sonarr ──→ qBittorrent  (download client — sends torrents for downloading)
Jellyseerr ──→ Radarr/Sonarr   (media requests — users request, *arr services fetch)
Jellyfin                        (serves the downloaded media library)
AdGuard Home                    (DNS rewriting: *.domain → Mac Mini LAN IP)
Traefik                         (reverse proxy + TLS termination for all services)
```

### Network Topology

All stacks share the `jellyfinnet` Docker network (`172.20.0.0/16`), enabling Traefik to route to any container by name.

- **VPN-namespaced services**: qBittorrent, Prowlarr, and FlareSolverr use `network_mode: "service:vpn"` — they share Gluetun's network stack. Ports and Traefik labels are defined on the Gluetun container.
- **Static IPs**: Radarr (`172.20.0.10`) and Sonarr (`172.20.0.11`) get static container IPs for stable inter-service communication.
- **DNS resolution**: AdGuard Home rewrites `*.domain` to the Mac Mini's LAN IP. Traefik uses `Host()` rules to route requests to the correct container.
- **TLS**: Traefik obtains Let's Encrypt wildcard certificates via Cloudflare DNS-01 challenge.

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| Docker Desktop for Mac | Container runtime |
| Python 3 + pip | Ansible and dependencies |
| Ansible | Service configuration automation |
| Cloudflare account + API token | DNS-01 challenge for TLS certificates |
| VPN account (PIA) | Torrent traffic routing via Gluetun |
| Domain name | Hostname-based routing for all services |

## Quick Start

### Fresh install (full stack)

```bash
# 1. Install Ansible collections and Python dependencies
make ansible-deps

# 2. Generate credentials (interactive — prompts for user-provided values, auto-generates the rest)
make generate-creds STACK=all

# 3. Deploy all stacks (management → networking → media → automation)
make deploy-all

# 4. Complete Jellyfin setup wizard at http://localhost:8096
#    (this is the one manual step — Jellyfin requires interactive setup)

# 5. Extract API keys from running containers
make extract-keys

# 6. Configure all services via their REST APIs
make ansible-sync
```

After step 6, all services are fully wired: Prowlarr syncs indexers to Sonarr/Radarr, both use qBittorrent as their download client, Jellyseerr can make requests to both, DNS rewriting is configured, and Uptime Kuma monitors everything.

### Deploy a single stack

```bash
make deploy-media        # Media services with VPN
make deploy-management   # Portainer, Watchtower, Uptime Kuma, Dozzle
make deploy-networking   # Traefik, AdGuard Home
make deploy-automation   # Semaphore
```

## Makefile Reference

| Target | Description |
|--------|-------------|
| `make deploy-media` | Start media stack with VPN profile |
| `make deploy-management` | Start management stack |
| `make deploy-networking` | Start networking stack |
| `make deploy-automation` | Start automation stack |
| `make deploy-all` | Start all stacks in dependency order |
| `make ansible-deps` | Install Ansible Galaxy collections + Python dependencies (run once, or after changing `requirements.yml`) |
| `make ansible-sync` | Run Ansible playbook to configure all services via REST APIs |
| `make vault-edit` | Edit encrypted vault secrets |
| `make generate-creds STACK=<name>` | Generate credentials for a stack (`common`, `networking`, `management`, `media`, `semaphore`, `all`) |
| `make extract-keys` | Extract API keys from running *arr containers + prompt for Jellyseerr key |

## Ansible Roles

After containers are running, `make ansible-sync` configures services via their REST APIs. All roles are idempotent — re-running produces no changes if already configured.

| Role | What it configures | Key actions |
|------|--------------------|-------------|
| **env_files** | All stacks | Renders `.env.j2` templates from vault variables (always runs first) |
| **qbittorrent** | qBittorrent | Sets download path, creates torrent categories (`tv-sonarr`, `radarr`) |
| **prowlarr** | Prowlarr | Adds Sonarr + Radarr as full-sync application targets |
| **sonarr** | Sonarr | Adds qBittorrent as download client, ensures root folders exist |
| **radarr** | Radarr | Adds qBittorrent as download client, ensures root folders exist |
| **jellyseerr** | Jellyseerr | Connects Radarr + Sonarr for media requests (skips if setup wizard not completed) |
| **recyclarr** | *(informational)* | Recyclarr self-manages via its own YAML config — no API to call |
| **adguard** | AdGuard Home | Configures DNS rewrites for wildcard domain resolution |
| **traefik** | *(informational)* | Routing is declarative via Docker labels — no API config needed |
| **uptime_kuma** | Uptime Kuma | Creates HTTP monitors for all services |

Role execution order matters: `env_files` must run first (generates `.env` files), and downstream roles depend on services being healthy (built-in health check retries handle this).

## Secrets Management

### How it works

1. **Ansible Vault** (`ansible/group_vars/all/vault.yml`) is the single source of truth for all secrets
2. **`.env.j2` templates** in each stack directory reference vault variables
3. The **`env_files` Ansible role** renders templates into `.env` files at deploy time
4. **`.env` files are gitignored** — they're generated artifacts, never committed

### Workflow

```bash
# Edit vault secrets
make vault-edit

# Generate credentials for a new setup
make generate-creds STACK=all    # Interactive — prompts for VPN creds, Cloudflare tokens, etc.

# Extract API keys from running *arr containers (writes them back to vault)
make extract-keys

# Regenerate .env files after vault changes
make ansible-sync                # env_files role runs first, then configures services
```

### What requires manual input

| Secret | Why it can't be automated |
|--------|---------------------------|
| VPN username/password | Provider account credentials |
| Cloudflare API tokens | Created in Cloudflare dashboard |
| Jellyfin credentials | Set during mandatory setup wizard |
| Domain name | User's registered domain |

Everything else (qBittorrent password, AdGuard credentials, Uptime Kuma credentials, Semaphore admin password, database passwords) is auto-generated by `make generate-creds`.

## Modular Deployment

### Service groups

The media stack uses Docker Compose profiles to control which services start:

| Profile | Services | Use case |
|---------|----------|----------|
| `vpn` | All core services + VPN tunnel | Standard deployment — movies, TV, audiobooks |
| `no-vpn` | Same services without VPN | Testing/development without VPN overhead |
| `recommendarr` | Recommendarr only | Optional AI-powered recommendations (add to `COMPOSE_PROFILES`) |

```bash
# Standard deployment (VPN profile — used by make deploy-media)
cd docker-media-stack && COMPOSE_PROFILES=vpn docker compose up -d

# With Recommendarr
cd docker-media-stack && COMPOSE_PROFILES=vpn,recommendarr docker compose up -d
```

### Stack independence

Each stack can be deployed and torn down independently:

```bash
make deploy-networking   # Just Traefik + AdGuard
make deploy-media        # Just media services
# No need to deploy management or automation if you don't want monitoring/UI
```

## Usage Scenarios

### Adding a new service

1. Add the service to the appropriate `docker-compose.yml`
2. Add Traefik labels for routing (`traefik.enable=true`, `Host()` rule, port)
3. If it needs secrets, add variables to `vault.yml` and the stack's `.env.j2` template
4. Create an Ansible role if the service has a REST API to configure
5. Add the role to `ansible/site.yml`
6. Add an Uptime Kuma monitor in `ansible/group_vars/all/vars.yml`
7. Add a DNS rewrite if it needs a subdomain (usually covered by the wildcard)

### Recovering after a Docker volume loss

Named volumes persist data across container restarts. If a volume is lost:

```bash
# Redeploy the affected stack
make deploy-media

# Re-extract API keys (they'll be regenerated by *arr services on fresh start)
make extract-keys

# Re-run Ansible to reconfigure everything
make ansible-sync
```

### Updating credentials

```bash
# Edit the vault
make vault-edit

# Regenerate .env files and reconfigure services
make ansible-sync

# Restart affected containers to pick up new .env values
cd docker-media-stack && docker compose up -d
```

## Debugging Guide

### DNS challenge fails (Traefik can't get TLS certificates)

**Symptom**: Traefik logs show ACME DNS-01 challenge failures.

**Cause**: DNS queries are routing through AdGuard, which rewrites the domain to the local IP, preventing the ACME challenge from verifying.

**Fix**: Ensure Traefik's certificate resolver uses external DNS:
```
--certificatesresolvers.letsencrypt.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53
```

### VPN port forwarding not working

**Symptom**: qBittorrent shows no incoming connections.

**Cause**: PIA streaming-optimized servers don't support port forwarding.

**Fix**: Use regular (non-streaming) servers and set `VPN_PORT_FORWARDING=on` in the media stack `.env`.

### Docker API version mismatch

**Symptom**: Traefik or Watchtower fails to start with Docker API version errors.

**Cause**: Docker Desktop for Mac auto-negotiates API versions differently than Linux Docker. Some containers hardcode an API version.

**Fix**:
- Traefik: use v3.6+ (supports API version auto-negotiation)
- Watchtower: set `DOCKER_API_VERSION=1.44` environment variable

### Service can't reach another service

**Symptom**: Connection refused between containers.

**Check**:
1. Are both services on the `jellyfinnet` network?
2. Is the target service VPN-namespaced? If so, use `vpn` as the hostname (not the container name)
3. Are the ports correct? Some images change default ports between versions (e.g., Dozzle v10+ uses port 8080, not 9999)

### Ansible role fails with "unreachable"

**Symptom**: `make ansible-sync` fails waiting for a service health check.

**Cause**: The container isn't running or hasn't finished starting.

**Fix**: Check that the stack is deployed (`docker compose ps`) and containers are healthy. Health check retries (12 attempts, 10 seconds apart = 2 minutes) should handle normal startup delays.

### bcrypt passwords in .env files

**Symptom**: Services reject passwords containing `$` characters.

**Cause**: Docker Compose interprets `$` as variable interpolation.

**Fix**: In `.env.j2` templates, use the Jinja2 filter `| replace('$', '$$')` to escape dollar signs.

## CI/CD

GitHub Actions validates the codebase on every push and pull request. **Deployment is not automated** — it remains manual via `make` targets since it requires local Docker access.

### What's validated

| Check | Tool | What it catches |
|-------|------|-----------------|
| YAML syntax | yamllint | Malformed YAML in compose files, Ansible roles, vars |
| Ansible best practices | ansible-lint | Deprecated modules, missing names, bad patterns |
| Shell script quality | shellcheck | Bash anti-patterns, quoting issues, undefined variables |
| Playbook syntax | ansible-playbook --syntax-check | Invalid task definitions, missing variables |
| Secret leaks | gitleaks | Accidentally committed passwords, API keys, tokens |

### Setup

One GitHub Secret is required:

- **`VAULT_PASSWORD`** — the Ansible Vault password, needed by `ansible-playbook --syntax-check` to parse encrypted variable references

Set it via: **Repository Settings → Secrets and variables → Actions → New repository secret**

## File Structure

```
HomeLab/
├── docker-media-stack/
│   ├── docker-compose.yml    # Jellyfin, *arr, qBittorrent, VPN, audiobooks
│   ├── .env.j2               # Jinja2 template for .env
│   └── .env.example          # Placeholder documentation
├── docker-management-stack/
│   ├── docker-compose.yml    # Portainer, Watchtower, Uptime Kuma, Dozzle
│   ├── .env.j2
│   └── .env.example
├── docker-networking-stack/
│   ├── docker-compose.yml    # Traefik, AdGuard Home
│   ├── .env.j2
│   └── .env.example
├── docker-automation-stack/
│   ├── docker-compose.yml    # Semaphore
│   ├── .env.j2
│   └── .env.example
├── ansible/
│   ├── site.yml              # Main playbook
│   ├── inventory/hosts.yml   # Localhost inventory
│   ├── requirements.yml      # Galaxy collections
│   ├── group_vars/all/
│   │   ├── vars.yml          # Non-secret variables
│   │   └── vault.yml         # Encrypted secrets (ansible-vault)
│   └── roles/
│       ├── env_files/        # Renders .env.j2 → .env
│       ├── qbittorrent/      # Download path, categories
│       ├── prowlarr/         # App sync to Sonarr/Radarr
│       ├── sonarr/           # Download client, root folders
│       ├── radarr/           # Download client, root folders
│       ├── jellyseerr/       # Radarr/Sonarr integration
│       ├── recyclarr/        # Informational (self-managed)
│       ├── adguard/          # DNS rewrites
│       ├── traefik/          # Informational (Docker labels)
│       └── uptime_kuma/      # HTTP monitors
├── scripts/
│   ├── generate-credentials.sh
│   └── extract-api-keys.sh
├── .github/workflows/
│   └── validate.yml          # CI pipeline
├── Makefile                  # Primary interface
├── CLAUDE.md                 # AI assistant instructions
└── README.md                 # This file
```
