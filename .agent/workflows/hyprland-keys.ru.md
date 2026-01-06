---
description: Настройка клавиш Hyprland
---

# Клавиши Hyprland

## Файлы конфигурации

| Файл | Назначение |
|------|------------|
| `files/gui/hypr/bindings/apps.conf` | Запуск приложений |
| `files/gui/hypr/bindings/special.conf` | Спецклавиши |
| `files/gui/hypr/bindings/wm.conf` | Управление окнами |

## Синтаксис

```
bind = MODS, KEY, ACTION, ARGS
```

### Модификаторы:

- `SUPER` (Mod4) — Windows/Super
- `SHIFT`
- `CTRL`
- `ALT`

## Примеры

### Запуск приложения:

```
bind = SUPER, Return, exec, kitty
bind = SUPER, D, exec, rofi -show drun
```

### Управление окнами:

```
bind = SUPER, Q, killactive
bind = SUPER, F, fullscreen
bind = SUPER, Space, togglefloating
```

### Рабочие столы:

```
bind = SUPER, 1, workspace, 1
bind = SUPER SHIFT, 1, movetoworkspace, 1
```

## Применение изменений

После редактирования:

```bash
hyprctl reload
```

## Отладка

Проверить активные привязки:

```bash
hyprctl binds
```
