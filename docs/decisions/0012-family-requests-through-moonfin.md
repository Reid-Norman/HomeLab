# 0012. Family requests inside the Moonfin app; Seerr off the internet

**Status:** accepted · **Date:** 2026-10-27

## Context

Non-technical family members should be able to request movies and TV on their own, from their phones and TVs (Android TV, Fire TV, Roku), as simply as possible and without weakening security. Until now they used Seerr's website at `requests.domain` through Cloudflare Tunnel, behind Cloudflare Access: an emailed code, then a Seerr login, on a separate site from the app they watch in.

Options considered:

- **Seerr's website with one login** (drop Cloudflare Access): simpler, but Seerr stays public and is still a separate site to remember.
- **Authelia single sign-on for family:** Seerr's OpenID Connect login is only in an experimental preview build, and Jellyfin's TV and phone apps can't sign in through Authelia; they'd still need Quick Connect codes.
- **The Jellyfin Enhanced plugin:** adds requesting to Jellyfin's web interface, but not to the TV apps.
- **Tailscale for family:** nothing public, but a VPN app that has to stay on is too much for non-technical users.
- **A chat bot** (Telegram or Discord): no login, but another app, and less polished.
- **[Moonfin](https://moonfin.io)**, a third-party Jellyfin app for phones and TVs, which has Seerr requests built in through its server plugin, Moonbase.

## Decision

- **Family use Moonfin** to watch and request. They sign in with their Jellyfin account, then sign in to Seerr once with the same account; Moonbase keeps that Seerr session on the server.
- **Seerr comes off the internet.** Moonbase calls Seerr at `http://seerr:5055` inside the Docker network, and Seerr's webhook calls Jellyfin at `http://jellyfin:8096`. The `requests` tunnel hostname and its Cloudflare Access app are removed. `requests.domain` becomes an alias of `seerr.domain` for the home network and Tailscale.
- **Family are Jellyfin users only.** Authelia users stay admins, so family can't reach the start page or admin pages.
- **New Seerr users get request and auto-approve,** with weekly limits per person (10 movies and 10 TV seasons by default), set by the `seerr` role.
- **Moonbase is installed and configured by the `jellyfin` role,** like the other plugins.

## Consequences

- Jellyfin and Audiobookshelf are the only public apps. Seerr's code is no longer exposed to the internet.
- One app and one password for family. Requests are auto-approved, and the limits stop one person from filling the disk.
- Moonbase is third-party code running inside Jellyfin with access to the server, and it holds family members' Seerr sessions. It's open source (GPL-2.0) and installed from its own plugin repository. If it stops being maintained, Jellyfin Enhanced is the fallback for phones, and the Seerr website over Tailscale works for the admin.
- Family members switch from the official Jellyfin app to Moonfin.
- The limits apply to new Seerr users. Existing users keep the permissions they already had until changed in Seerr.
