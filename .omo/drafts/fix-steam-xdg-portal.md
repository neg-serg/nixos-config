# Draft: fix-steam-xdg-portal

## Intent
- **Intent**: CLEAR
- **Review required**: false

## Decisions
- Заменить `xdg-desktop-portal-shana` + `xdg-desktop-portal-kde` на `xdg-desktop-portal-gtk`
- Маршрутизировать `org.freedesktop.impl.portal.FileChooser` напрямую на `gtk` (без shana-прослойки)
- Удалить конфиг shana из yazi.nix (мёртвый код)
- Опционально: сузить kill-паттерн в hypr-start

## Status
- **Status**: awaiting-approval → approved
- **Pending action**: write .omo/plans/fix-steam-xdg-portal.md

## Ledger
- `modules/user/xdg.nix` — основной файл изменений (portal бэкенды + конфиг)
- `modules/user/nix-maid/cli/yazi.nix` — удалить shana конфиг
- `modules/user/nix-maid/hyprland/services.nix` — опционально: сузить kill

## Research summary
См. полный анализ в разговоре. Ключевые причины зависания:
1. KDE portal требует KIO/klauncher/plasma-workspace — не работают под Hyprland
2. shana OnceLock кеширует сломанное D-Bus соединение
3. Нет таймаута на shana proxy .await → вечное зависание
4. Hyprland portal не имплементирует FileChooser (by design)
