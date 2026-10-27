# 0011. Scan compose hardening on every push, images weekly

**Status:** accepted · **Date:** 2026-10-27

## Context

CI already ran gitleaks, so secrets were covered. Nothing checked the containers. This repo has no application code and no Dockerfiles: it is compose files that run about twenty third-party images. So there are two places a problem can come from:

- **How we run the containers.** A privileged container or a Docker socket mount gives that container root on the host. Before this, nothing stopped a new service being added with either, and no service set `no-new-privileges`.
- **What's inside the images.** Watchtower pulls `:latest` without looking, so nothing showed whether an image is still maintained, or when a pinned tag (Authelia, Postgres, Uptime Kuma, Homepage) has fallen behind.

Semgrep's registry ruleset for compose (`p/docker-compose`) matched nothing here, not even a test file with a privileged container. Every rule in it requires a top-level `version:` key, which Compose v2 files don't have.

## Decision

- **Semgrep with our own rules** (`.semgrep/compose.yml`, adapted from the registry rules without the `version:` requirement) runs on every push and PR and fails the build on: a privileged container, a Docker socket mount, a service without `no-new-privileges:true`, or disabled seccomp/AppArmor/SELinux. Checkov and Trivy were considered, but neither reads compose files.
- **Every service runs with `no-new-privileges`.** All 22 were redeployed with it and checked; none needed an exception.
- **Socket mounts are suppressed inline with the reason** (`# nosemgrep: docker-socket-mount — <reason>`): Traefik reads labels, Portainer and Watchtower manage containers, Dozzle streams logs. A suppression without a reason doesn't pass review. Mounting the socket `:ro` was not used as a fix: it only makes the socket file read-only, and the Docker API behind it still accepts writes.
- **Trivy scans every image weekly, report-only.** It reports fixable HIGH and CRITICAL CVEs for `linux/arm64` (the server's platform) to GitHub code scanning. It doesn't block PRs, because the images don't change with our commits and we can't patch them: the fix is to bump a tag or replace the image.
- **Both workflows get a read-only token** (`permissions: contents: read`); only the upload job can write security events.

## Consequences

- Adding a service without `no-new-privileges`, or with a socket mount and no reason, fails CI.
- Traefik, Portainer, Watchtower and Dozzle still have full Docker API access. A read-only socket proxy for Traefik and Dozzle would narrow that, but isn't done yet.
- The first trial scan found an image well behind its Debian base (Shelfmark) and fixable CVEs in the pinned Authelia 4.39. Someone has to read the weekly results; the runbook is in [Operations](../operations.md#act-on-an-image-scan).
- Rules we maintain ourselves don't get upstream updates. There are four of them, so that's acceptable.
