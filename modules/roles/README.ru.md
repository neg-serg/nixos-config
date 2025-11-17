# Роли: краткая шпаргалка

- Включайте роль в конфиге хоста:

  - `roles.workstation.enable = true;` — рабочая станция (профиль производительности, SSH, Avahi,
    Syncthing).
  - `roles.homelab.enable = true;` — селф‑хостинг (профиль безопасности, DNS, SSH, Syncthing, MPD,
    Navidrome, Wakapi, Nextcloud).
  - `roles.media.enable = true;` — медиа‑серверы (Jellyfin, Navidrome, MPD, Avahi, SSH).
  - `roles.server.enable = true;` — headless/сервер по умолчанию (включает smartd по умолчанию).

- Переопределяйте тумблеры сервисов через `profiles.services.<name>.enable` (алиас:
  `servicesProfiles.<name>.enable`).

  - Пример: `profiles.services.jellyfin.enable = false;`

- Типичные дальнейшие шаги по ролям:

  - Workstation: настроить стек игр в `profiles.games.*` и `modules/user/games`.
  - Homelab: задать DNS‑переписывания в `servicesProfiles.adguardhome.rewrites`, определить
    устройства/папки Syncthing в `hosts/<host>/services.nix`.
  - Media: указать пути/порты для MPD/Navidrome; Jellyfin открывает нужные порты сам при включении.

- Документация: агрегированные опции доступны через flake‑артефакт
  `packages.${system}."options-md"`, когда собран.
