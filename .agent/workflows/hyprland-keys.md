______________________________________________________________________

## description: Configure Hyprland keybindings / Настройка клавиш Hyprland

# Hyprland Keybindings / Клавиши Hyprland

## Configuration Files / Файлы конфигурации

| File | Purpose / Назначение | |------|---------------------| | `files/gui/hypr/bindings/apps.conf`
| Application launchers | | `files/gui/hypr/bindings/special.conf` | Special keys | |
`files/gui/hypr/bindings/wm.conf` | Window management |

## Syntax / Синтаксис

```
bind = MODS, KEY, ACTION, ARGS
```

### Modifiers / Модификаторы:

- `SUPER` (Mod4) — Windows/Super key
- `SHIFT`
- `CTRL`
- `ALT`

## Examples / Примеры

### Launch application / Запуск приложения:

```
bind = SUPER, Return, exec, kitty
bind = SUPER, D, exec, rofi -show drun
```

### Window control / Управление окнами:

```
bind = SUPER, Q, killactive
bind = SUPER, F, fullscreen
bind = SUPER, Space, togglefloating
```

### Workspaces / Рабочие столы:

```
bind = SUPER, 1, workspace, 1
bind = SUPER SHIFT, 1, movetoworkspace, 1
```

## Apply Changes / Применение изменений

After editing / После редактирования:

```bash
hyprctl reload
```

## Debug / Отладка

Check active bindings / Проверить активные привязки:

```bash
hyprctl binds
```
