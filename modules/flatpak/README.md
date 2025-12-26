# Flatpak Module / Модуль Flatpak

Flatpak integration for containerized applications.

Интеграция Flatpak для контейнерных приложений.

## Configuration / Конфигурация

```nix
services.flatpak.enable = true;
```

## Usage / Использование

```bash
flatpak install flathub org.example.App
flatpak run org.example.App
```
