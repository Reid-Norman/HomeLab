# HomeLab

Self-hosted media and infrastructure automation. Docker Compose provisions containers; Ansible configures services via their REST APIs. All secrets live in Ansible Vault — nothing is manually configured that can be automated.

## Design Principles

- **Maximize automation, minimize interaction** — the challenge is automating as much as possible. Human input is only required where unavoidable (initial VPN credentials, Cloudflare tokens, Jellyfin setup wizard). Everything else is scripted via `make` targets and Ansible API calls.
- **Reproducibility** — a fresh server should reach full functionality from `make deploy-all && make ansible-sync`.
- **Modularity** — services are grouped by purpose (media streaming, audiobooks, management, networking). Deploy only what you need via Docker Compose profiles and selective `make` targets. Not everyone wants audiobooks; not everyone needs Recommendarr.
- **Secrets as code** — all credentials live in Ansible Vault. `.env` files are generated artifacts, never edited by hand.
- **Idempotency** — every command is safe to re-run. `make ansible-sync` only changes what's needed.
- **Declarative infrastructure** — Docker labels define routing, Ansible vars define service config, vault defines secrets.

## Architecture

### Stacks

| Stack | Services | Purpose |
|-------|----------|---------|
| **docker-networking-stack** | Traefik, AdGuard Home, Cloudflared *(optional `tunnel` profile)* | How traffic gets in: reverse proxy, TLS, security headers, DNS, public tunnel |
| **docker-management-stack** | Portainer, Watchtower, Uptime Kuma, Dozzle | Watching and running the server: containers, monitoring, logs, auto-updates |
| **docker-media-stack** | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Seerr, Recyclarr, FlareSolverr, Gluetun VPN, Recommendarr, Shelfmark, Audiobookshelf | Media acquisition, streaming, and audiobooks |
| **docker-automation-stack** | Semaphore | Ansible UI for running playbooks from a browser |

### Stack layout

Each stack has one purpose, and dependencies only point down: a stack may rely on the ones above it in this list, never the ones below.

1. **networking**: the foundation. Every other stack's routes go through its Traefik. It doesn't depend on any other stack, so it's reusable on its own as a reverse proxy + DNS + tunnel setup.
2. **management**: tools that look after the other stacks. Optional; nothing depends on it.
3. **media**: the apps. Needs networking only for its `*.domain` URLs; on direct ports it runs alone. No Cloudflare account needed, because the tunnel lives in networking.
4. **automation**: Semaphore, which runs the Ansible playbooks. Optional.

Optional pieces are Compose profiles (`tunnel` in networking; `media`, `audiobooks`, `recommendarr` in media), so you can deploy only what you need. `make deploy-all` deploys in this order, and `make down-all` stops them in reverse.

### Service Relationships

```
Prowlarr ──→ Radarr/Sonarr     (indexer sync — Prowlarr pushes indexers to both)
Radarr/Sonarr ──→ qBittorrent  (download client — sends torrents for downloading)
Seerr ──→ Radarr/Sonarr        (media requests — users request, *arr services fetch)
Jellyfin                        (serves the downloaded media library)
Shelfmark ──→ Prowlarr          (audiobook indexer search)
Shelfmark ──→ qBittorrent       (audiobook download client)
Audiobookshelf                  (serves the audiobook library)
AdGuard Home                    (DNS rewriting: *.domain → server LAN IP)
Traefik                         (reverse proxy + TLS termination for all services)
```

### Network Topology

All stacks share the `homelab-network` Docker network (`172.20.0.0/16`), enabling Traefik to route to any container by name.

- **VPN-namespaced services**: qBittorrent, Prowlarr, and FlareSolverr use `network_mode: "service:vpn"` — they share Gluetun's network stack. Ports and Traefik labels are defined on the Gluetun container.
- **Static IPs**: Radarr (`172.20.0.200`) and Sonarr (`172.20.0.201`) get static container IPs in the high end of the subnet to avoid conflicts with Docker's dynamic allocation. These are needed for Prowlarr (inside the VPN namespace) to reach them.
- **DNS resolution**: AdGuard Home rewrites `*.domain` to the server's LAN IP. Traefik uses `Host()` rules to route requests to the correct container.
- **Security headers**: every HTTPS route through Traefik gets HSTS (6 months, including subdomains, no preload), `X-Content-Type-Options: nosniff` and a strict referrer policy, via the `security-headers` middleware on the `websecure` entrypoint. Cloudflare adds HSTS to the tunnel hostnames, which don't pass through Traefik.
- **TLS**: Traefik obtains one Let's Encrypt wildcard certificate (`domain` + `*.domain`) via the Cloudflare DNS-01 challenge. Only the Traefik dashboard router requests it. TLS is on for the whole `websecure` entrypoint, so every other router reuses that certificate with no `certresolver` label, and individual subdomain names stay out of public Certificate Transparency logs. Don't add `certresolver` to other routers or to the entrypoint: Traefik would then request a separate certificate per router.

## Accessing Services

There are two ways in:

| Path | Hostnames | How it works |
|------|-----------|--------------|
| **Public** (Cloudflare Tunnel) | `jellyfin.domain`, `requests.domain` (Seerr, behind Cloudflare Access), `audiobooks.domain` | `cloudflared` connects out to Cloudflare. No ports are opened on the router, and Cloudflare serves HTTPS |
| **Home network** | All hostnames below | A public DNS-only record `*.domain` points to the server's LAN IP, and Traefik routes by hostname using the wildcard certificate. That IP is private, so these names only connect from inside the home network |

The `cloudflare_dns` role creates the `*.domain` record (Cloudflare, *DNS only*, not proxied) on every `make ansible-sync`. Because it's public DNS, every device finds these names with whatever DNS it already uses, so nothing on the network depends on the server being up. The tunnel hostnames are more specific records, so they still go through the tunnel. Give the server a DHCP reservation so its IP doesn't change after a reboot.

Check from any device with `dig +short seerr.domain`. It should return the server's LAN IP.

- Publishing a private (`192.168.x.x`) IP reveals nothing reachable from outside. It does show that the domain has a home network behind it.
- A few routers and DNS filters have *DNS rebinding protection*, which drops public answers that contain private IPs. If `dig` returns nothing on one network, allow the domain in that router's rebinding settings.
- Work laptops on a full-tunnel VPN usually can't reach home-network IPs at all. That's the VPN's policy, not a DNS problem.

AdGuard Home's `*.domain` rewrite still exists for devices that choose AdGuard as their DNS (for ad blocking). It gives the same answer.

| Service | Hostname | Service | Hostname |
|---------|----------|---------|----------|
| Jellyfin | `jellyfin.domain` | Portainer | `portainer.domain` |
| Seerr | `seerr.domain` (also `jellyseerr.domain`) | Uptime Kuma | `uptime-kuma.domain` |
| Sonarr | `sonarr.domain` | Dozzle | `dozzle.domain` |
| Radarr | `radarr.domain` | Semaphore | `semaphore.domain` |
| Prowlarr | `prowlarr.domain` | AdGuard Home | `adguard.domain` |
| qBittorrent | `qbittorrent.domain` | Traefik dashboard | `traefik.domain` |
| Shelfmark | `shelfmark.domain` | Audiobookshelf | `audiobookshelf.domain` |
| Recommendarr | `recommendarr.domain` | | |

### Recommended Cloudflare settings

These live in the Cloudflare dashboard, not in this repo:

- **SSL/TLS → Edge Certificates**: turn on *Always Use HTTPS* and *HSTS*, and set *Minimum TLS Version* to 1.2.
- **Security → WAF → Rate limiting rules**: limit requests to `jellyfin.domain/Users/AuthenticateByName` (for example, 5 per minute per IP) to slow password guessing. Jellyfin is public with no Cloudflare Access because its apps can't get past a login page.
- **API token**: the token Traefik uses only needs *Zone → DNS → Edit* on this one zone.

## Prerequisites

| Requirement | Install | Purpose |
|-------------|---------|---------|
| Docker / Docker Compose | [Docker Desktop](https://www.docker.com/products/docker-desktop/) (macOS/Windows) or [Docker Engine](https://docs.docker.com/engine/install/) (Linux) | Container runtime |
| Python 3 | `brew install python` (macOS) or `apt install python3` (Linux) | Ansible runtime |
| Ansible | `pip3 install ansible` | Service configuration automation |
| Cloudflare account | [Dashboard](https://dash.cloudflare.com/) | DNS-01 challenge for TLS certificates |
| VPN account (PIA) | [Sign up](https://www.privateinternetaccess.com/) | Torrent traffic routing via Gluetun |
| Domain name | Any registrar | Hostname-based routing for all services |

> **Note**: This project was developed on macOS with Docker Desktop. On Linux, you may need to adjust the Docker socket path and ensure `/dev/net/tun` is available for the VPN container.

## Quick Start

### Fresh install (full stack)

```bash
# 1. Install Ansible collections and Python dependencies
make ansible-deps

# 2. Generate credentials (interactive — prompts for user-provided values, auto-generates the rest)
make generate-creds STACK=all

# 3. Create the shared Docker network
docker network create --subnet=172.20.0.0/16 homelab-network

# 4. Deploy all stacks (networking → management → media → automation)
make deploy-all

# 5. Complete post-deployment manual steps (see section below)

# 6. Extract API keys from running containers
make extract-keys

# 7. Configure all services via their REST APIs
make ansible-sync
```

After step 7, all services are fully wired: Prowlarr syncs indexers to Sonarr/Radarr, both use qBittorrent as their download client, Seerr can make requests to both, DNS rewriting is configured, and Uptime Kuma monitors everything.

### Deploy a single stack

```bash
make deploy-media        # Movies & TV only
make deploy-audiobooks   # Audiobooks only
make deploy-media-full   # All media services
make deploy-management   # Portainer, Watchtower, Uptime Kuma, Dozzle
make deploy-networking   # Traefik, AdGuard Home
make deploy-automation   # Semaphore
```

## Makefile Reference

| Target | Description |
|--------|-------------|
| `make deploy-media` | Start media stack (movies & TV profile) |
| `make deploy-audiobooks` | Start media stack (audiobooks profile) |
| `make deploy-media-full` | Start media stack (all profiles) |
| `make deploy-management` | Start management stack |
| `make deploy-networking` | Start networking stack, including the Cloudflare Tunnel (`NETWORKING_PROFILES=` to leave it out) |
| `make deploy-automation` | Start automation stack |
| `make deploy-all` | Start all stacks in dependency order |
| `make down-all` | Stop all stacks in reverse dependency order |
| `make ansible-deps` | Install Ansible Galaxy collections + Python dependencies (run once, or after changing `requirements.yml`) |
| `make ansible-sync` | Run Ansible playbook to configure all services via REST APIs |
| `make vault-edit` | Edit encrypted vault secrets |
| `make generate-creds STACK=<name>` | Generate credentials for a stack (`common`, `networking`, `management`, `media`, `semaphore`, `all`) |
| `make extract-keys` | Extract API keys from running Radarr, Sonarr, and Prowlarr containers into the vault |

## Modular Deployment

### Service profiles

The media stack uses Docker Compose profiles to control which services start:

| Profile | Services | Use case |
|---------|----------|----------|
| `media` | VPN, qBittorrent, Prowlarr, FlareSolverr, Radarr, Sonarr, Jellyfin, Seerr, Recyclarr | Movies & TV |
| `audiobooks` | VPN, qBittorrent, Prowlarr, FlareSolverr, Shelfmark, Audiobookshelf | Audiobooks |
| `recommendarr` | Recommendarr | Optional AI-powered recommendations (add to `COMPOSE_PROFILES`) |

Shared services (VPN, qBittorrent, Prowlarr, FlareSolverr) start with **either** `media` or `audiobooks` — they're in both profiles.

```bash
# Movies & TV only
make deploy-media

# Audiobooks only
make deploy-audiobooks

# Everything (movies, TV, and audiobooks)
make deploy-media-full

# Everything + Recommendarr
cd docker-media-stack && COMPOSE_PROFILES=media,audiobooks,recommendarr docker compose up -d
```

### Stack independence

Each stack can be deployed and torn down independently:

```bash
make deploy-networking                       # Traefik + AdGuard + Cloudflare Tunnel
make deploy-networking NETWORKING_PROFILES=  # Traefik + AdGuard, no tunnel or Cloudflare Tunnel token
make deploy-media                            # Just media services
# No need to deploy management or automation if you don't want monitoring/UI
```

## Post-Deployment Manual Steps

These steps require manual interaction and cannot be automated:

1. **Jellyfin setup wizard** — Complete initial setup at `http://localhost:8096` (creates admin user, configures media libraries)

2. **Prowlarr indexer configuration** — Add indexers manually in Prowlarr's UI (`http://localhost:9696`). Indexers require account credentials, captchas, and session tokens that can't be automated. Prowlarr will automatically sync configured indexers to Sonarr/Radarr via `make ansible-sync`.

3. **Shelfmark initial setup** (if using audiobooks profile):
   - Connect to Prowlarr: `http://vpn:9696`
   - Configure qBittorrent as download client: `http://vpn:5080`, category: `audiobooks`, with the qBittorrent username/password from the vault (`make vault-edit`)
   - Set library paths for book organization

4. **Audiobookshelf library setup** (if using audiobooks profile) — Add `/media/audiobooks` as the audiobook library folder in the Audiobookshelf UI (`http://localhost:13378`)

5. **Recommendarr** (if using recommendarr profile) — Configure your AI service (OpenAI API key or Ollama endpoint) in the Recommendarr UI (`http://localhost:3000`)

6. **Uptime Kuma cleanup** — When a service is renamed or removed, add its old monitor name to `uptime_kuma_retired_monitors` in `vars.yml` and `make ansible-sync` deletes it. Monitors that predate this list (e.g., "LazyLibrarian") can be added there or deleted in the Uptime Kuma UI.

7. **Seerr setup wizard** (fresh installs only) — Complete setup at `http://localhost:5055` by signing in with your Jellyfin admin account, then run `make ansible-sync` to connect Radarr and Sonarr. Existing Jellyseerr data migrates automatically (see [Migrating from Jellyseerr](#migrating-from-jellyseerr-to-seerr)).

## Ansible Roles

After containers are running, `make ansible-sync` configures services via their REST APIs. All roles are idempotent — re-running produces no changes if already configured.

| Role | What it configures | Key actions |
|------|--------------------|-------------|
| **env_files** | All stacks | Renders `.env.j2` templates from vault variables (always runs first) |
| **qbittorrent** | qBittorrent | Sets download path, max seeding time (10 days), creates torrent categories (`tv-sonarr`, `radarr`, `audiobooks`), syncs the listening port to the VPN forwarded port, requires login for every client outside the VPN namespace |
| **prowlarr** | Prowlarr | Adds Sonarr + Radarr as full-sync application targets |
| **sonarr** | Sonarr | Adds qBittorrent as download client, ensures root folders exist |
| **radarr** | Radarr | Adds qBittorrent as download client, ensures root folders exist |
| **seerr** | Seerr | Connects Radarr + Sonarr for media requests (skips if setup wizard not completed) |
| **recyclarr** | *(informational)* | Recyclarr self-manages via its own YAML config — no API to call |
| **cloudflare_dns** | Cloudflare DNS | Keeps the DNS-only `*.domain` record pointed at the server's LAN IP |
| **adguard** | AdGuard Home | Configures DNS rewrites for wildcard domain resolution and sets encrypted (DNS-over-HTTPS) upstream resolvers |
| **traefik** | *(informational)* | Routing is declarative via Docker labels — no API config needed |
| **uptime_kuma** | Uptime Kuma | Creates HTTP monitors for all services; removes monitors listed in `uptime_kuma_retired_monitors` |

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

## Usage Scenarios

### Adding a new service

1. Add the service to the appropriate `docker-compose.yml`
2. Add Traefik labels for routing (`traefik.enable=true`, `Host()` rule, `websecure` entrypoint, port). TLS comes from the shared wildcard certificate, so don't add a `certresolver` label
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

### Migrating from Jellyseerr to Seerr

Jellyseerr and Overseerr merged into [Seerr](https://docs.seerr.dev/), and the Jellyseerr image is frozen at `2.7.3-deprecated`. Newer Jellyfin releases reject its sign-in request, so Jellyfin logins fail. Seerr imports Jellyseerr data automatically on first start.

What changed in this repo:

| Before | After |
|--------|-------|
| `fallenbagel/jellyseerr:latest` | `ghcr.io/seerr-team/seerr:latest` (with `init: true`) |
| Service/container `jellyseerr` | `seerr` (network alias `jellyseerr` kept) |
| Volume `jellyseerr-config` | `seerr-config` (must be owned by UID 1000) |
| `jellyseerr.domain` | `seerr.domain` (`jellyseerr.domain` still routes) |
| Ansible role `jellyseerr` | `seerr` |
| Uptime Kuma monitor "Jellyseerr" | "Seerr" (old monitor removed automatically) |

To migrate an existing install's data into the new volume (stop Jellyseerr first):

```bash
docker stop jellyseerr && docker rm jellyseerr
docker volume create docker-media-stack_seerr-config
docker run --rm -v docker-media-stack_jellyseerr-config:/src:ro \
  -v docker-media-stack_seerr-config:/dst alpine \
  sh -c 'cp -a /src/. /dst/ && chown -R 1000:1000 /dst'
make deploy-media && make ansible-sync
```

The old `jellyseerr-config` volume is left in place for rollback. Once Seerr has been working for a while, remove it with `docker volume rm docker-media-stack_jellyseerr-config`.

**Cloudflare Tunnel:** the tunnel's public hostname for Seerr is `requests.domain`, pointing to `http://jellyseerr:5055`. It keeps working through the `jellyseerr` network alias. To drop the alias later, change the tunnel's service URL to `http://seerr:5055` in the Cloudflare dashboard.

## Debugging Guide

### DNS challenge fails (Traefik can't get TLS certificates)

**Symptom**: Browsers show "not secure" on home-network hostnames, and the certificate is `TRAEFIK DEFAULT CERT` or expired. Traefik logs show ACME DNS-01 failures such as `could not find zone ... i/o timeout`.

Check which certificate is being served:
```bash
echo | openssl s_client -connect <server-lan-ip>:443 -servername seerr.domain 2>/dev/null \
  | openssl x509 -noout -text | grep -E "Issuer:|Not After|DNS:"
```

**Cause 1**: DNS queries are routing through AdGuard, which rewrites the domain to the local IP, preventing the ACME challenge from verifying.

**Fix**: Make sure Traefik's certificate resolver uses external DNS (already set in the networking stack):
```
--certificatesresolvers.cloudflare.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53
```

**Cause 2**: A VPN app on the host (for example, the PIA desktop app with its DNS leak protection) blocks DNS traffic to everything except its own resolver. This affects Docker containers too. Test with `dig +time=3 SOA domain @1.1.1.1`: a timeout means DNS is being blocked.

**Fix**: Don't run a desktop VPN on the server. Gluetun already routes torrent traffic through the VPN on its own. Once DNS works, Traefik retries and renews automatically within a few minutes. AdGuard's upstreams use DNS-over-HTTPS by IP, so lookups for LAN devices keep working even while port 53 is blocked.

### VPN port forwarding not working

**Symptom**: qBittorrent shows no incoming connections.

**Cause**: PIA streaming-optimized servers don't support port forwarding.

**Fix**: Use regular (non-streaming) servers and set `VPN_PORT_FORWARDING=on` in the media stack `.env`.

qBittorrent's listening port must match the port PIA forwards, which can change on reconnect. Gluetun's `VPN_PORT_FORWARDING_UP_COMMAND` pushes each new port to qBittorrent automatically, and `make ansible-sync` re-syncs it as a backstop. Check with `docker exec vpn cat /tmp/gluetun/forwarded_port` against qBittorrent's **Settings → Connection → Listening port**.

The up command can skip logging in because Ansible enables qBittorrent's **Bypass authentication for clients on localhost**. Localhost here is the VPN container's network, shared only by Gluetun, qBittorrent, Prowlarr and FlareSolverr. Browsers, Traefik, Sonarr and Radarr connect from Docker addresses (e.g. `172.20.0.1`), so Ansible also turns off the subnet whitelist, and those clients must log in.

### Docker API version mismatch

**Symptom**: Traefik or Watchtower fails to start with Docker API version errors.

**Cause**: Docker Desktop for Mac auto-negotiates API versions differently than Linux Docker. Some containers hardcode an API version.

**Fix**:
- Traefik: use v3.6+ (supports API version auto-negotiation)
- Watchtower: set `DOCKER_API_VERSION=1.44` environment variable

### Service can't reach another service

**Symptom**: Connection refused between containers.

**Check**:
1. Are both services on the `homelab-network` network?
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
│   ├── docker-compose.yml    # Jellyfin, *arr, qBittorrent, VPN, Shelfmark, Audiobookshelf
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
│       ├── cloudflare_dns/   # Public DNS-only *.domain record → server LAN IP
│       ├── qbittorrent/      # Download path, seeding time, categories, VPN port sync, auth
│       ├── prowlarr/         # App sync to Sonarr/Radarr
│       ├── sonarr/           # Download client, root folders
│       ├── radarr/           # Download client, root folders
│       ├── seerr/            # Radarr/Sonarr integration
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
