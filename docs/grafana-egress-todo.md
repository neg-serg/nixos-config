# Grafana: potential egress sources (TODO)

Goal: gather reasons for Grafana’s outbound connections in one place and decide what to block vs.
explicitly allow.

Current state (host telfir)

- Disabled: analytics, update checks, news feed, external snapshots, alpha plugins.
- Gravatar disabled (no external avatars).
- System egress restriction for the Grafana service:
  - `IPAddressDeny=any`, `IPAddressAllow=127.0.0.0/8 ::1/128` — the service cannot reach the
    Internet.
- Admin password provided via SOPS secret and `$__file{...}`.

Symptoms

- “Grafana is sending traffic” can be either server‑side egress (the service itself) or client‑side
  browser traffic when viewing the UI.

Possible egress sources

1. Browser (client‑side)

- Map/Geomap tiles from public tile servers.
- Fonts/icons/images from external CDNs if a panel/theme references them.
- Embedded panels with URLs outside your LAN.

2. Grafana service (server‑side)

- Plugin marketplace (catalog, icons, signatures) and auto‑updates.
- Alerting webhooks (Slack/Telegram/…): won’t deliver with strict egress block.
- Datasources pointing to external URLs (JSON/CSV/Infinity/Prometheus/Loki in the cloud).
- OAuth login to external providers (Google/GitHub, etc.).
- Image or panel rendering that tries to fetch external resources (rare).

What is already prevented by config

- `analytics.reporting_enabled=false`, `check_for_updates=false`, `news_feed_enabled=false`,
  `snapshots.external_enabled=false`.
- `plugins.disable_install_api=true` (plugin install UI off), `users.allow_gravatar=false`.
- System egress block via `IPAddressDeny/Allow` (loopback only).

TODO (decide and/or document)

- [ ] Keep service egress fully closed? If not, document a minimal allow‑list of IPs/subnets for
  concrete needs (e.g., alerting webhooks) and where to configure it.
- [ ] Alerting: either use local Alertmanager or define explicit exceptions for required external
  receivers.
- [ ] Panels with maps/external resources: note in README that this is browser traffic and not
  controlled by Grafana service settings.
- [ ] CSP/Headers via Caddy: add a stricter CSP if needed to avoid external scripts/fonts/images in
  UI.
- [ ] Plugins: define install policy — only via Nix/derivations, or one‑off install followed by
  “freezing” the directory (tmpfiles wipes plugins on activation).
- [ ] Document how to temporarily relax egress for local debugging (temporary `IPAddressAllow` +
  restart).
- [ ] Verify that there are no datasources pointing outside localhost/LAN.

Diagnostics

- Unit network limits: `systemctl show -p IPAddressDeny -p IPAddressAllow grafana.service`
- Service logs: `journalctl -u grafana -b`
- Process sockets/conns: `sudo ss -tpn | rg grafana`
- Incoming traffic (Caddy): `sudo tail -f /var/lib/caddy/logs/grafana_access.log`

Notes

- Even with service egress blocked, the user’s browser can still make external requests — this is
  expected for some panels (e.g., map tiles). If undesired, use local tile servers or panels without
  external resources.
