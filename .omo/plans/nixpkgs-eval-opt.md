# Nixpkgs Module Eval Optimization — 4.3s → 2-3s

## TL;DR (For humans)

Сейчас nixpkgs загружает **~1000 модулей** (веб-серверы, БД, CI/CD, X11, печать, VoIP, ...) которые никогда не используются на odin. Каждый модуль добавляет option-декларации (даже если сервис выключен), и система тратит ~3s только на их слияние. Наши 350 модулей — лишь ~12% от этого времени.

**План — 2 волны:**

1. **disabledModules** — явно отключить загрузку категорий nixpkgs, которые гарантированно не нужны. Самый сильный рычаг (~1-1.5s), но требует осторожности.
2. **Остальное** — сократить flake inputs (20 из 24 используются только в devShells), уменьшить персональный nix.settings overhead, убрать лишние eval-опции.

### 1. disabledModules: отключить ненужные категории nixpkgs

Список категорий, которые гарантированно не нужны на odin (Wayland, домашняя рабочая станция, нет веб-серверов/БД/печати/X11/VoIP):

```
## Веб-серверы и прокси
"services/web-servers/nginx/default.nix"
"services/web-servers/apache-httpd/default.nix"  
"services/web-servers/caddy/default.nix"
"services/web-servers/traefik/default.nix"
"services/web-servers/haproxy/default.nix"
"services/web-servers/varnish/default.nix"

## Базы данных
"services/databases/postgresql.nix"
"services/databases/mysql.nix"
"services/databases/mariadb.nix"
"services/databases/redis.nix"
"services/databases/mongodb.nix"
"services/databases/influxdb.nix"
"services/databases/clickhouse.nix"
"services/databases/cassandra.nix"
"services/databases/neo4j.nix"
"services/databases/cockroachdb.nix"

## CI/CD
"services/continuous-integration/jenkins"
"services/continuous-integration/gitlab-runner.nix"
"services/continuous-integration/buildbot"

## Мониторинг (неиспользуемые)
"services/monitoring/prometheus.nix"
"services/monitoring/alertmanager.nix" 
"services/monitoring/loki.nix"
"services/monitoring/grafana-image-renderer.nix"
"services/monitoring/thanos.nix"
"services/monitoring/telegraf.nix"
"services/monitoring/zabbix"

## X11 (мы на Wayland)
"services/x11/xserver.nix" (осторожно — может быть транзитивной зависимостью)
"services/x11/desktop-managers"
"services/x11/window-managers"

## Печать
"services/printing/cupsd.nix"

## Mail servers
"services/mail/postfix.nix"
"services/mail/dovecot.nix"
"services/mail/rspamd.nix"
"services/mail/opensmtpd.nix"

## VoIP
"services/networking/asterisk.nix"
"services/networking/mumble.nix"
"services/networking/jitsi"

## K8s / container orchestration
"services/cluster/kubernetes"
"services/cluster/nomad"

## Misc server services
"services/misc/gitlab.nix"
"services/misc/gitea.nix"
"services/misc/plex.nix"
"services/misc/jellyfin.nix"  — осторожно, проверь не используется ли
"services/misc/emby.nix"
"services/misc/matrix-synapse.nix"
"services/misc/paperless.nix"
"services/misc/nextcloud.nix"  — осторожно
"services/misc/n8n.nix"
```

### 2. Flake inputs — 20 из 24 только для devShells

При `--refresh --offline` eval не качает сеть, но каждый input всё равно резолвится из lockfile. Можно:

- Вынести devShell-только inputs в отдельный `outputs.devShells` с ленивой загрузкой
- Или просто удалить неиспользуемые (caelestia-shell, sshell, wrapper-manager — не используются в nixosConfigs)

### 3. nix.settings тюнинг

Уже включено, но проверить:
- `eval-cache = true` ✅
- `eval-system = "x86_64-linux"` ✅
- `allow-import-from-derivation = false` ✅
- `lazy-locks = true` ✅ (Determinate Nix)

Добавить:
- `pure-eval = true` ✅ (уже)
- Проверить что нет лишних `nix.settings` которые форсят eval

## Todos

### 1. Запустить eval-profiler flamegraph для точного профилирования

- **Что**: `nix eval --option eval-profiler flamegraph --option eval-profile-file /tmp/nix-flamegraph.folded '.#nixosConfigurations.odin.config.system.build.toplevel.name'`
- **Результат**: файл `/tmp/nix-flamegraph.folded` — прочитать и найти топ-10 функций по времени
- **Acceptance**: Получен список самых дорогих модулей/функций
- **QA**: `head -20 /tmp/nix-flamegraph.folded`

### 2. Составить безопасный disabledModules список для odin

- **Файл**: `hosts/odin/default.nix` (или `modules/nix/disabled.nix`)
- **Что**: Добавить `disabledModules` с категориями, которые гарантированно не нужны
- **Метод**: Итеративный — добавлять по 5-10 модулей, проверять `nh os switch --dry`, если падает — выяснять транзитивную зависимость
- **Acceptance**: eval падает ≥0.5s за каждые 50 отключённых модулей
- **QA**: `nh os switch --dry` проходит без ошибок

### 3. Убрать devShell-only flake inputs из ранней загрузки

- **Файлы**: `flake.nix`
- **Что**: Проверить, какие из 20 devShell-только inputs можно:
  - (a) Удалить совсем (неиспользуемые: caelestia-shell, sshell, wrapper-manager?)
  - (b) Зафолловить за nixpkgs (уже сделано для большинства)
  - (c) Сделать `flake = false` где возможно (уменьшает lock-файл)
- **Acceptance**: `nix flake lock` проходит, lock-файл стал меньше
- **QA**: `nix flake show` показывает все ожидаемые outputs

### F1. Замер времени после disabledModules

- **Что**: `time nix eval --refresh --offline '.#nixosConfigurations.odin.config.system.build.toplevel.name'`
- **Target**: ≤3.5s после добавления disabledModules

### F2. Regression: nh os switch --dry

- **QA**: `nh os switch --dry` без ошибок

### F3. Regression: nix flake check

- **QA**: `nix flake check` — все проверки проходят

## Must-NOT-Have
- Не отключать модули, которые используются транзитивно (systemd unit dependencies, option defaults для включённых сервисов)
- Не ломать `nh os switch` и `nix flake check`
- Не удалять flake inputs, которые используются в nixosConfigurations
