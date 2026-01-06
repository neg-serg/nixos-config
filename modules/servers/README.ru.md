# Модуль серверов

Профили серверов и конфигурация сервисов.

## Включение сервисов

```nix
profiles.services.<name>.enable = true;
# или
servicesProfiles.<name>.enable = true;
```

## Доступные сервисы

| Сервис | Порт | Описание |
|--------|------|----------|
| `openssh` | 22/TCP | SSH сервер |
| `mpd` | 6600/TCP | Music Player Daemon |
| `jellyfin` | 8096/TCP | Стриминг медиа |
| `adguardhome` | 53, 3000 | Фильтрация DNS |
| `unbound` | 5353/TCP | DNS резолвер |
| `duckdns` | - | Динамический DNS |

## Стек DNS

```
Apps → systemd-resolved (127.0.0.53) → AdGuardHome (127.0.0.1:53) → Unbound (127.0.0.1:5353)
```

## Проверка DNS

```bash
systemctl status adguardhome unbound systemd-resolved
ss -lntup | rg ':53|:5353'
resolvectl status
resolvectl query example.com
```

## Политика

- Без warnings при eval — модули не должны вызывать `warnings`, `trace`, `lib.warn`
