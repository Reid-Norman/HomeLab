# Getting started

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| Docker Desktop (macOS/Windows) or Docker Engine (Linux) | Container runtime |
| Python 3 and Ansible (`pip3 install ansible`) | Service configuration |
| A domain on Cloudflare | DNS-01 certificates, the DNS-only wildcard record, the tunnel |
| A VPN account (PIA) | Torrent traffic through Gluetun |
| Tailscale account *(optional)* | Remote admin access |

!!! note
    Developed on macOS with Docker Desktop. On Linux, check the Docker socket path and that `/dev/net/tun` exists for the VPN container.

## Fresh install

```bash
# 1. Ansible collections and Python dependencies
make ansible-deps

# 2. Credentials: prompts for what only you can provide (VPN, Cloudflare, domain),
#    generates everything else, and writes it all to Ansible Vault
make generate-creds STACK=all

# 3. The shared Docker network
docker network create --subnet=172.20.0.0/16 homelab-network

# 4. Render .env files and Authelia config from the vault
make env

# 5. Deploy all stacks (networking → auth → management → media → automation)
make deploy-all

# 6. Do the manual steps below

# 7. Pull the API keys the apps generated on first start into the vault
make extract-keys

# 8. Configure everything through the services' APIs
make ansible-sync
```

After step 8 everything is wired: Prowlarr syncs indexers to Sonarr and Radarr, both use qBittorrent, Seerr can request from both, DNS records and rewrites exist, Uptime Kuma monitors every service, and the *arr apps hand their login to Authelia.

## Manual steps

These need a person and can't be automated:

1. **Authelia two-factor:** open any admin page, sign in, register an authenticator app. The confirmation link is in `docker exec authelia cat /data/notification.txt`.
2. **Jellyfin setup wizard** at `http://localhost:8096`: admin user and libraries.
3. **Prowlarr indexers** at `http://localhost:9696`: they need accounts and captchas. `make ansible-sync` then syncs them to Sonarr and Radarr.
4. **Seerr setup wizard** at `http://localhost:5055` (fresh installs): sign in with your Jellyfin admin, then `make ansible-sync` connects Radarr and Sonarr.
5. **Shelfmark** (audiobooks profile): Prowlarr at `http://vpn:9696`, qBittorrent at `http://vpn:5080` with category `audiobooks`.
6. **Audiobookshelf** (audiobooks profile): add `/media/audiobooks` as a library.
7. **Recommendarr** (recommendarr profile): add your AI provider.
8. **Tailscale** *(optional)*: see [Remote access](access.md#remote-access-tailscale).

## Choosing what to deploy

| Profile | Services | Use case |
|---------|----------|----------|
| `media` | VPN, qBittorrent, Prowlarr, FlareSolverr, Radarr, Sonarr, Jellyfin, Seerr | Movies and TV |
| `audiobooks` | VPN, qBittorrent, Prowlarr, FlareSolverr, Shelfmark, Audiobookshelf | Audiobooks |
| `recommendarr` | Recommendarr | Optional AI recommendations |
| `tunnel` (networking) | cloudflared | Public access to Jellyfin, Seerr, Audiobookshelf |

```bash
make deploy-media                            # movies and TV
make deploy-audiobooks                       # audiobooks
make deploy-media-full                       # both
make deploy-networking NETWORKING_PROFILES=  # without the tunnel or a Cloudflare Tunnel token
cd docker-media-stack && COMPOSE_PROFILES=media,audiobooks,recommendarr docker compose up -d
```

## Makefile reference

| Target | Description |
|--------|-------------|
| `make env` | Render `.env` files and Authelia config from the vault only (no API calls). Run before deploying a stack whose config changed |
| `make deploy-networking` | Networking stack, including the tunnel (`NETWORKING_PROFILES=` to leave it out) |
| `make deploy-auth` | Auth stack (Authelia) |
| `make deploy-management` | Management stack |
| `make deploy-media` / `deploy-audiobooks` / `deploy-media-full` | Media stack with the matching profiles |
| `make deploy-automation` | Automation stack |
| `make deploy-all` / `make down-all` | All stacks, in dependency order / reverse |
| `make ansible-deps` | Install Ansible collections (once, or after changing `requirements.yml`) |
| `make ansible-sync` | Run the playbook: render config, then configure every service |
| `make vault-edit` | Edit the encrypted vault |
| `make generate-creds STACK=<name>` | Generate credentials (`common`, `networking`, `auth`, `management`, `media`, `semaphore`, `all`) |
| `make extract-keys` | Copy Radarr, Sonarr and Prowlarr API keys from the running containers into the vault |
