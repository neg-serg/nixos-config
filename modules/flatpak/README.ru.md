# Модуль Flatpak

Интеграция Flatpak для контейнерных приложений.

## Конфигурация

```nix
services.flatpak.enable = true;
```

## Использование

```bash
flatpak install flathub org.example.App
flatpak run org.example.App
```
