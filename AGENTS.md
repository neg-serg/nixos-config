# AGENTS: Tips and pitfalls found while wiring monitoring and Nextcloud

This repo uses a custom `post-boot.target`, Nextcloud via PHP‑FPM behind Caddy, and Prometheus exporters. Below are the key gotchas we hit and the fixes that worked, so we don’t step on the same rakes again.

Post‑Boot Systemd Target
- Don’t add `After=graphical.target` to the `post-boot.target` itself; `graphical.target` already wants `post-boot.target`. Adding `After=graphical.target` on the target creates an ordering cycle.
- When deferring services to post‑boot, avoid blanket `After=graphical.target` in the helper that attaches units to `post-boot.target`. Let the target be wanted by `graphical.target`, and only add specific `After=` edges per service if strictly required (never the target itself).

Wi‑Fi via iwd profile
- The base network module installs iwd tooling but sets `networking.wireless.iwd.enable = false` so wired hosts don’t start it needlessly.
- To give a host Wi‑Fi controls, toggle `profiles.network.wifi.enable = true;` (e.g. inside `hosts/<name>/networking.nix`) instead of hand-written `lib.mkForce` overrides.

Prometheus PHP‑FPM Exporter + Nextcloud pool
- Socket access: the exporter scrapes `unix:///run/phpfpm/nextcloud.sock;/status`. Ensure the PHP‑FPM pool socket is group‑readable by a shared web group and the exporter joins it:
  - `services.phpfpm.pools.nextcloud.settings`: set `"listen.group" = "nginx";` and `"listen.mode" = "0660"`.
  - Add both `caddy` and `prometheus` users to the `nginx` group via `users.users.<name>.extraGroups = [ "nginx" ];`.
- Unit sandboxing: the upstream exporter unit can prohibit UNIX sockets with `RestrictAddressFamilies`.
  - Allow AF_UNIX: set `RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];`.
  - Ensure the unit has access to the socket group: `SupplementaryGroups = [ "nginx" ];`.
- DynamicUser vs. real user: the upstream module may use `DynamicUser=true` and `Group=php-fpm-exporter`. If you need the exporter to inherit static group membership, override with higher priority:
  - `DynamicUser = lib.mkForce false; User = lib.mkForce "prometheus"; Group = lib.mkForce "prometheus";`.
- Startup order: start the exporter after the Nextcloud PHP‑FPM pool is up to avoid initial connection failures:
  - `after = [ "phpfpm-nextcloud.service" "phpfpm.service" "nextcloud-setup.service" ];`
  - `wants = [ "phpfpm-nextcloud.service" ];`

Emergency switch safety
- If activation is blocked by the exporter while debugging, temporarily disable it to unblock a `switch`: set `services.prometheus.exporters."php-fpm".enable = false;` and re‑enable after fixing permissions/ordering.

Common mistakes to avoid
- Misplacing user group options: within the `users = { ... }` attrset, set `users.caddy.extraGroups = [ "nginx" ];` and `users.prometheus.extraGroups = [ "nginx" ];` (this maps to `users.users.<name>.extraGroups`). Don’t write `users.users.caddy` again inside `users = { ... }` — that becomes `users.users.users.caddy` and fails evaluation.
- Enabling multiple proxies: don’t enable both `nextcloud.nginxProxy` and `nextcloud.caddyProxy` together (there’s an assertion protecting this, but worth remembering).
