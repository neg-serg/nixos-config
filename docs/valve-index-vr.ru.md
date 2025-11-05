# Valve Index VR на Hyprland (AMD Radeon RX 7900 XTX)

## Пересборка и включение сервисов
- Выполните `sudo nixos-rebuild switch --flake /etc/nixos#telfir`, чтобы применить VR‑стек.
- Перезагрузите систему один раз, чтобы параметры ядра, правила udev и пользовательские сервисы корректно подхватились.

## Мини‑проверки SteamVR
- Запустите Steam и установите пакет SteamVR (если ещё не установлен).
- В настройках SteamVR → Developer → Set Current OpenXR Runtime выберите «SteamVR».
- Запустите SteamVR; проверьте, что композитор стартует и показывает домашнее пространство без ошибок.

## Опциональная диагностика
- `openxr-info` (из `vulkan-tools`) — вывод информации о рантайме.
- `vkcube` и `vkcube --display` — проверка Vulkan‑ускорения и X11‑fallback.
- Для раскладок контроллеров проверьте `~/.local/share/Steam/config/steamvr.vrsettings` после привязки, чтобы убедиться, что профили ввода подхватились.

