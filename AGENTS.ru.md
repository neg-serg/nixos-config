# AGENTS: советы и грабли при интеграции мониторинга и Nextcloud

В репозитории используется кастомная цель `post-boot.target`, Nextcloud через PHP‑FPM за Caddy, и экспортеры Prometheus. Ниже — основные грабли и рабочие фиксы, чтобы не наступать повторно.

Post‑Boot Systemd Target
- Не добавляйте `After=graphical.target` в сам `post-boot.target`; `graphical.target` уже хочет `post-boot.target`. Добавление `After=graphical.target` на target создаёт цикл упорядочивания.
- Перенося сервисы на post‑boot, избегайте безусловного `After=graphical.target` в хелпере, который цепляет юниты к `post-boot.target`. Пусть target будет wanted графическим таргетом, а конкретные `After=` добавляйте только по необходимости (никогда не на сам target).

Профиль Wi‑Fi (iwd)
- Базовый сетевой модуль ставит тулзы iwd, но держит `networking.wireless.iwd.enable = false`, чтобы проводные хосты не поднимали сервис.
- Если на хосте нужен Wi‑Fi, включите `profiles.network.wifi.enable = true;` (например, в `hosts/<имя>/networking.nix`) вместо ручного `lib.mkForce`.

Prometheus PHP‑FPM Exporter + пул Nextcloud
- Доступ к сокету: экспортер читает `unix:///run/phpfpm/nextcloud.sock;/status`. Убедитесь, что сокет пула PHP‑FPM доступен на чтение группе общего веб‑пула, и экспортер входит в неё:
  - `services.phpfpm.pools.nextcloud.settings`: `"listen.group" = "nginx";`, `"listen.mode" = "0660"`.
  - Добавьте пользователей `caddy` и `prometheus` в группу `nginx` через `users.users.<name>.extraGroups = [ "nginx" ];`.
- Песочница юнита: апстрим‑юнит экспортера может запрещать UNIX‑сокеты через `RestrictAddressFamilies`.
  - Разрешите AF_UNIX: `RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];`.
  - Дайте юниту доступ к группе сокета: `SupplementaryGroups = [ "nginx" ];`.
- DynamicUser vs. постоянный пользователь: апстрим может использовать `DynamicUser=true` и `Group=php-fpm-exporter`. Чтобы экспортер наследовал статическое членство в группах, переопределите с большим приоритетом:
  - `DynamicUser = lib.mkForce false; User = lib.mkForce "prometheus"; Group = lib.mkForce "prometheus";`.
- Порядок запуска: стартовать экспортер после того, как поднят пул Nextcloud PHP‑FPM, чтобы избежать начальных ошибок подключения:
  - `after = [ "phpfpm-nextcloud.service" "phpfpm.service" "nextcloud-setup.service" ];`
  - `wants = [ "phpfpm-nextcloud.service" ];`

Экстренная безопасность switch
- Если при отладке экспортер блокирует активацию, временно отключите его, чтобы разблокировать `switch`: `services.prometheus.exporters."php-fpm".enable = false;` и включите обратно после фикса прав/порядка.

Типовые ошибки
- Неправильное место для extraGroups: внутри `users = { ... }` задавайте `users.caddy.extraGroups = [ "nginx" ];` и `users.prometheus.extraGroups = [ "nginx" ];` (это маппится на `users.users.<name>.extraGroups`). Не пишите повторно `users.users.caddy` внутри `users = { ... }` — получится `users.users.users.caddy` и сломает оценку.
- Двойное включение прокси: не включайте одновременно `nextcloud.nginxProxy` и `nextcloud.caddyProxy` (есть assertion, но помнить полезно).
