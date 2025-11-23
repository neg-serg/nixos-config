# Серверы: включение/настройка/порты

- Включайте профиль сервиса через `profiles.services.<name>.enable` (алиас:
  `servicesProfiles.<name>.enable`).
- Специфичные настройки задавайте в `services.<name>.*` как обычно.

Политика: без предупреждений при оценке

- Модули в этом репозитории не должны издавать предупреждения/трейсы во время оценки.
- Избегайте `warnings = [ .. ]`, `builtins.trace`, `lib.warn`. Предпочитайте документацию и чёткие
  описания опций.

Примеры и порты

- openssh: `profiles.services.openssh.enable = true;`
  - Порты: 22/TCP (открывается модулем автоматически)
- mpd: `profiles.services.mpd.enable = true;`
  - Порты: 6600/TCP (открывается модулем)
- jellyfin: `profiles.services.jellyfin.enable = true;`
  - Типичный порт: 8096/TCP (меняйте в конфиге сервиса при необходимости)
- adguardhome: `profiles.services.adguardhome.enable = true;`
  - DNS на 53/UDP+TCP (upstreams/rewrites: `servicesProfiles.adguardhome.rewrites`)
  - Админ‑UI по умолчанию: 3000/TCP, привязан к 127.0.0.1
  - Листы фильтров:
    `servicesProfiles.adguardhome.filterLists = [ { name, url, enabled ? true } ... ]`
  - Рекомендуемая связка: приложения → systemd-resolved (127.0.0.53) → AdGuardHome (127.0.0.1:53) →
    Unbound (127.0.0.1:5353).
  - Жёсткость resolved: отключить LLMNR/mDNS для предсказуемого резолвинга (`LLMNR=no`,
    `MulticastDNS=no`).
- unbound: `profiles.services.unbound.enable = true;`
  - Слушает 127.0.0.1:5353 и используется как upstream для AdGuardHome.
  - Режимы (выбор `servicesProfiles.unbound.mode`):
    - `recursive` — чистая рекурсия (без форвардеров); DNSSEC можно переключать `dnssec.enable`.
    - `dot` (по умолчанию) — DNS‑over‑TLS форвардеры из `dotUpstreams` (формат `host@port#SNI`).
    - `doh` — DNS‑over‑HTTPS через локальный `dnscrypt-proxy2` (слушает `doh.listenAddress`, по
      умолчанию 127.0.0.1:5053).
      - Настройте DoH‑апстримы `doh.serverNames` (например, `["cloudflare" "quad9-doh"]`).
      - Опциональный `doh.sources` переопределяет список резолверов, используемый dnscrypt-proxy2.
  - DNSSEC: `servicesProfiles.unbound.dnssec.enable = true;` (по умолчанию включено).
  - Тюнинг (надёжность/задержки): `servicesProfiles.unbound.tuning.*`
    - `minimalResponses` (по умолчанию true)
    - `prefetch`, `prefetchKey` (по умолчанию true)
    - `aggressiveNsec` (по умолчанию true)
    - `serveExpired.enable` (по умолчанию true), `serveExpired.maxTtl` (по умолчанию 3600),
      `serveExpired.replyTtl` (по умолчанию 30)
    - `cacheMinTtl` / `cacheMaxTtl` (null = оставить дефолты Unbound)
    - Логи: `verbosity` (по умолчанию 1), флаги `logQueries`, `logReplies`, `logLocalActions`,
      `logServfail` (по умолчанию false)
  - Мониторинг: Prometheus‑экспортер + дашборд Grafana для задержек DNS, валидации DNSSEC и
    кэш‑хитов — см. `docs/unbound-metrics.ru.md`.

## Проверка DNS

- Сервисы: `systemctl status adguardhome unbound systemd-resolved`
- Порты: `ss -lntup | rg ':53|:5353|:5053'`
  - ожидается: resolved → 127.0.0.53:53; AdGuardHome → 127.0.0.1:53; Unbound → 127.0.0.1:5353;
    dnscrypt-proxy2 → 127.0.0.1:5053 (если mode="doh")
- Маршрутизация DNS: `resolvectl status` → `DNS Servers: 127.0.0.1`, `Domains: ~.`
- Фильтры AGH: `journalctl -u adguardhome -b | rg -i 'filter|download|update|enabled'`
- Быстрый запрос: `resolvectl query example.com` (должно идти через цепочку)
Документация

- Опции по сервисам в агрегированном файле: flake‑артефакт `packages.${system}."options-md"` (когда
  собран).
- Каждый модуль также экспортирует стандартные опции `services.*`.
