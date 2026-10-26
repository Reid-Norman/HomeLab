# Operations

## Ansible roles

`make ansible-sync` runs `ansible/site.yml` against `localhost`. Every role is idempotent: a second run reports no changes unless something drifted.

| Role | What it does |
|------|--------------|
| **env_files** | Renders every `.env.j2`, `homepage.env.j2` and Authelia's config from the vault (mode 0600), restarting Authelia or Homepage when theirs changed. Always first; `make env` runs only this |
| **cloudflare_tunnel** | Informational: the tunnel is token-based and its hostnames live in the Cloudflare dashboard |
| **cloudflare_dns** | Keeps the DNS-only `*.domain` record pointed at the server's LAN IP |
| **tailscale** | Reports whether Tailscale is logged in, routes the server's IP and has key expiry off. Never fails the run |
| **qbittorrent** | Download path, seeding limit (10 days), categories, listening port synced to the VPN's forwarded port, and the narrow login bypass |
| **prowlarr** | Adds Sonarr and Radarr as full-sync apps; hands its login to Authelia |
| **sonarr** / **radarr** | qBittorrent as download client, root folders; hand their login to Authelia |
| **jellyfin** | Plugin repositories and plugins (skips without an API key) |
| **seerr** | Connects Radarr and Sonarr (skips until the setup wizard is done) |
| **recyclarr** | Informational placeholder; Recyclarr isn't deployed |
| **adguard** | `*.domain` rewrite and DNS-over-HTTPS upstreams |
| **traefik** | Informational: routing is Docker labels |
| **authelia** / **homepage** | Health checks; their config is rendered by `env_files` |
| **uptime_kuma** | One HTTP monitor per service, Telegram alerts, removes retired monitors |
| **semaphore** | Logs in through the API and creates the HomeLab project |

Conventions every role follows:

- Ansible runs on the host, so roles call `http://localhost:<port>`, never container names.
- Tasks that handle credentials have `no_log: true`.
- Health checks retry 12 times, 10 seconds apart.
- Optional pieces skip with a message instead of failing.

## Secrets

1. **Ansible Vault** (`ansible/group_vars/all/vault.yml`, encrypted) is the single source of truth.
2. **Templates** (`.env.j2`, `homepage.env.j2`, `authelia/*.j2`) reference vault variables.
3. **`env_files`** renders them into gitignored files with mode 0600.
4. **CI** only holds the vault password, for the playbook syntax check. gitleaks scans every push.

Only four kinds of secret need a person: the VPN account, Cloudflare tokens, the Jellyfin admin (set in its wizard) and the domain. `make generate-creds` generates the rest: service passwords, database passwords, Authelia's secrets and its argon2id password hash.

```bash
make vault-edit                    # change a secret
make env                           # re-render config files
make deploy-<stack>                # recreate containers whose config changed
make ansible-sync                  # re-apply API configuration
```

## Runbooks

### Add a service

1. Add it to the right stack's `docker-compose.yml`. Pick the stack by [dependency direction](architecture.md#stack-layout) and where its secrets would end up.
2. Add Traefik labels: `traefik.enable=true`, a `Host()` rule, the `websecure` entrypoint and the port. No `certresolver` label: the wildcard covers it.
3. If it's an admin page, add `traefik.http.routers.<name>.middlewares=${ADMIN_MIDDLEWARES}` and publish its port on `127.0.0.1` only.
4. Put secrets in the vault and the stack's `.env.j2`.
5. Add an Ansible role if it has an API to configure, and add it to `site.yml`.
6. Add an Uptime Kuma monitor in `vars.yml` and a tile in `docker-management-stack/homepage/services.yaml`.

### Recover from a lost volume

```bash
make deploy-<stack>     # recreates the volume empty
make extract-keys       # *arr apps generate new API keys on a fresh start
make ansible-sync       # reconfigures everything
```

Then redo the [manual steps](getting-started.md#manual-steps) for that service.

### Reset the Authelia password

```bash
make vault-edit                  # set vault_authelia_password_hash to "REPLACE_AUTHELIA_PASSWORD_HASH"
make generate-creds STACK=auth   # prints the new password once
make env                         # renders it and restarts Authelia
```

Three wrong passwords lock the account for 10 minutes. The username is `admin`, not an email address.

### Rename or remove a service

Add the old monitor name to `uptime_kuma_retired_monitors` in `vars.yml`; `make ansible-sync` deletes it from Uptime Kuma.

### Migrate Jellyseerr data to Seerr

Seerr imports Jellyseerr data on first start. To copy an existing install into the new volume:

```bash
docker stop jellyseerr && docker rm jellyseerr
docker volume create docker-media-stack_seerr-config
docker run --rm -v docker-media-stack_jellyseerr-config:/src:ro \
  -v docker-media-stack_seerr-config:/dst alpine \
  sh -c 'cp -a /src/. /dst/ && chown -R 1000:1000 /dst'
make deploy-media && make ansible-sync
```

The `jellyseerr` network alias and hostname are kept, so old links and the tunnel's `http://jellyseerr:5055` keep working. Background: [ADR 0002](decisions/0002-seerr-migration.md).

## CI

GitHub Actions runs on every push and pull request. Deployment stays manual, because it needs the local Docker host.

| Check | Tool |
|-------|------|
| YAML syntax and style | yamllint |
| Ansible best practices | ansible-lint (production profile) |
| Shell scripts | shellcheck |
| Playbook syntax | `ansible-playbook --syntax-check` (needs the `VAULT_PASSWORD` secret; skipped without it) |
| Secret leaks | gitleaks, over the full commit range |
| These docs | `mkdocs build --strict`, then deploy to GitHub Pages from `main` |
