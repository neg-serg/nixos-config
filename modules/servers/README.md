# Servers Module / Модуль серверов

Server profiles and service configuration.

Профили серверов и конфигурация сервисов.

## Enable Services / Включение сервисов

```nix
profiles.services.<name>.enable = true;
# or / или
servicesProfiles.<name>.enable = true;
```

## Available Services / Доступные сервисы

| Service | Port | Description / Описание | |---------|------|------------------------| | `openssh`
| 22/TCP | SSH server | | `mpd` | 6600/TCP | Music Player Daemon | | `jellyfin` | 8096/TCP | Media
streaming | | `adguardhome` | 53, 3000 | DNS filtering | | `unbound` | 5353/TCP | DNS resolver | |
`duckdns` | - | Dynamic DNS |

## DNS Stack / Стек DNS

```
Apps → systemd-resolved (127.0.0.53) → AdGuardHome (127.0.0.1:53) → Unbound (127.0.0.1:5353)
```

## DNS Healthcheck / Проверка DNS

```bash
systemctl status adguardhome unbound systemd-resolved
ss -lntup | rg ':53|:5353'
resolvectl status
resolvectl query example.com
```

## Policy / Политика

- No eval warnings — modules must not emit `warnings`, `trace`, or `lib.warn`
- Без warnings при eval — модули не должны вызывать `warnings`, `trace`, `lib.warn`
