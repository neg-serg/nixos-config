# Servers: enable/config/ports

- Enable a server profile via `profiles.services.<name>.enable` (alias:
  `servicesProfiles.<name>.enable`).
- Configure service‑specific settings under `services.<name>.*` as usual.

Policy: no eval warnings

- Modules in this repo must not emit evaluation‑time warnings or traces.
- Avoid `warnings = [ .. ]`, `builtins.trace`, `lib.warn`. Prefer docs and clear option
  descriptions.

Examples and ports

- openssh: `profiles.services.openssh.enable = true;`
  - Ports: 22/TCP (opened automatically by the module)
- mpd: `profiles.services.mpd.enable = true;`
  - Ports: 6600/TCP (opened by module)
- jellyfin: `profiles.services.jellyfin.enable = true;`
  - Typical port: 8096/TCP (change in service config as needed)
- adguardhome: `profiles.services.adguardhome.enable = true;`
  - DNS on 53/UDP+TCP (configure upstreams/rewrites via `servicesProfiles.adguardhome.rewrites`)
  - Admin UI default in module: 3000/TCP bound to 127.0.0.1
  - Filter lists: `servicesProfiles.adguardhome.filterLists = [ { name, url, enabled ? true } ... ]`
  - Integration path (recommended): apps → systemd-resolved (127.0.0.53) → AdGuardHome
    (127.0.0.1:53) → Unbound (127.0.0.1:5353).
  - Resolved hardening: disable LLMNR/mDNS for predictable resolution (`LLMNR=no`,
    `MulticastDNS=no`).
- unbound: `profiles.services.unbound.enable = true;`
  - Listens on 127.0.0.1:5353 and is used as upstream for AdGuardHome.
  - Modes (select via `servicesProfiles.unbound.mode`):
    - `recursive` — pure recursion (no forwarders); DNSSEC validation can be toggled via
      `dnssec.enable`.
    - `dot` (default) — DNS-over-TLS forwarders from `dotUpstreams` (format: `host@port#SNI`).
    - `doh` — DNS-over-HTTPS via local `dnscrypt-proxy2` (listens at `doh.listenAddress`, default
      127.0.0.1:5053).
      - Configure DoH upstreams with `doh.serverNames` (e.g., `["cloudflare" "quad9-doh"]`).
      - Optional `doh.sources` overrides the default resolver list used by dnscrypt-proxy2.
  - DNSSEC: `servicesProfiles.unbound.dnssec.enable = true;` (enabled by default).
  - Tuning (reliability/latency): `servicesProfiles.unbound.tuning.*`
    - `minimalResponses` (default true)
    - `prefetch`, `prefetchKey` (default true)
    - `aggressiveNsec` (default true)
    - `serveExpired.enable` (default true), `serveExpired.maxTtl` (default 3600),
      `serveExpired.replyTtl` (default 30)
    - `cacheMinTtl` / `cacheMaxTtl` (null by default = leave Unbound defaults)
    - Logging: `verbosity` (default 1), and toggles `logQueries`, `logReplies`, `logLocalActions`,
      `logServfail` (all default false)
  - Monitoring: Prometheus exporter + Grafana dashboard for DNS latency, DNSSEC validation and cache
    hits — see `docs/unbound-metrics.md`.

## DNS Healthcheck

- Service status: `systemctl status adguardhome unbound systemd-resolved`
- Listening ports: `ss -lntup | rg ':53|:5353|:5053'`
  - expected: resolved → 127.0.0.53:53; AdGuardHome → 127.0.0.1:53; Unbound → 127.0.0.1:5353;
    dnscrypt-proxy2 → 127.0.0.1:5053 (if mode="doh")
- DNS routing: `resolvectl status` → `DNS Servers: 127.0.0.1`, `Domains: ~.`
- AGH filters: `journalctl -u adguardhome -b | rg -i 'filter|download|update|enabled'`
- Quick query: `resolvectl query example.com` (should resolve via the chain)
Docs

- See per‑service options in aggregated file: flake output `packages.${system}."options-md"` (when
  available).
- Each module also exposes standard NixOS options under `services.*`.
