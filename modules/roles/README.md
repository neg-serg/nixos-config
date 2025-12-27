# Roles: Quick Reference / Справочник по ролям

## Enable Roles / Включение ролей

```nix
roles.workstation.enable = true;  # Desktop defaults / Настройки рабочей станции
roles.homelab.enable = true;      # Self-hosting defaults / Домашний сервер
roles.media.enable = true;        # Media servers / Медиа сервера
roles.server.enable = true;       # Headless/server defaults / Серверные настройки
```

## Role Features / Возможности ролей

| Role | Features / Возможности | |------|----------------------| | `workstation` | Performance
profile, SSH, Avahi | | `homelab` | Security profile, DNS, SSH, MPD | | `media` | Jellyfin, MPD,
Avahi, SSH | | `server` | Headless, smartd by default |

## Override Services / Переопределение сервисов

```nix
profiles.services.<name>.enable = false;
# Example / Пример:
profiles.services.jellyfin.enable = false;
```

## Typical Next Steps / Следующие шаги

- **Workstation**: Adjust games in `profiles.games.*` and `modules/user/games`
- **Homelab**: Set DNS rewrites in `servicesProfiles.adguardhome.rewrites`
- **Media**: Set media paths/ports for MPD
