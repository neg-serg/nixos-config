# Справочник по ролям

## Включение ролей

```nix
roles.workstation.enable = true;  # Настройки рабочей станции
roles.homelab.enable = true;      # Домашний сервер
roles.media.enable = true;        # Медиа сервера
roles.server.enable = true;       # Серверные настройки
```

## Возможности ролей

| Роль | Возможности |
|------|-------------|
| `workstation` | Профиль производительности, SSH, Avahi |
| `homelab` | Профиль безопасности, DNS, SSH, MPD |
| `media` | Jellyfin, MPD, Avahi, SSH |
| `server` | Headless, smartd по умолчанию |

## Переопределение сервисов

```nix
profiles.services.<name>.enable = false;
# Пример:
profiles.services.jellyfin.enable = false;
```

## Следующие шаги

- **Workstation**: Настроить игры в `profiles.games.*` и `modules/user/games`
- **Homelab**: Установить DNS rewrites в `servicesProfiles.adguardhome.rewrites`
- **Media**: Установить медиа-пути/порты для MPD
