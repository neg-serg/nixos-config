# Servers: enable/config/ports

- Enable a server profile via `profiles.services.<name>.enable` (alias: `servicesProfiles.<name>.enable`).
- Configure service‑specific settings under `services.<name>.*` as usual.

Policy: no eval warnings
- Modules in this repo must not emit evaluation‑time warnings or traces.
- Avoid `warnings = [ .. ]`, `builtins.trace`, `lib.warn`. Prefer docs and clear option descriptions.

Examples and ports
- openssh: `profiles.services.openssh.enable = true;`
  - Ports: 22/TCP (opened automatically by the module)
- syncthing: `profiles.services.syncthing.enable = true;`
  - Ports: 8384/TCP (GUI), 22000/TCP+UDP (sync), 21027/UDP (discovery)
  - Host devices/folders go under `hosts/<host>/services.nix`.
- mpd: `profiles.services.mpd.enable = true;`
  - Ports: 6600/TCP (opened by module)
- navidrome: `profiles.services.navidrome.enable = true;`
  - Typical port: 4533/TCP (configure via `services.navidrome.settings.Port`)
- jellyfin: `profiles.services.jellyfin.enable = true;`
  - Typical port: 8096/TCP (change in service config as needed)
- adguardhome: `profiles.services.adguardhome.enable = true;`
  - DNS on 53/UDP+TCP (configure upstreams/rewrites via `servicesProfiles.adguardhome.rewrites`)
  - Admin UI default in module: 3000/TCP bound to 127.0.0.1
- unbound: `profiles.services.unbound.enable = true;`
  - Example here: 5353/TCP on localhost (as upstream for AdGuardHome)
- nextcloud: `profiles.services.nextcloud.enable = true;`
  - Reverse proxy: enable `services.nextcloud.{caddyProxy|nginxProxy}.enable = true;`
  - Open HTTP/HTTPS (80/443) when using proxy modules; internal PHP‑FPM socket is configured by the module.

Docs
- See per‑service options in aggregated file: flake output `packages.${system}."options-md"` (when available).
- Each module also exposes standard NixOS options under `services.*`.
