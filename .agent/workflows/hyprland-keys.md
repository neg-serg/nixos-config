---
description: Configure Hyprland keybindings
---

# Hyprland Keybindings

## Configuration Files

| File | Purpose |
|------|---------|
| `files/gui/hypr/bindings/apps.conf` | Application launchers |
| `files/gui/hypr/bindings/special.conf` | Special keys |
| `files/gui/hypr/bindings/wm.conf` | Window management |

## Syntax

```
bind = MODS, KEY, ACTION, ARGS
```

### Modifiers:

- `SUPER` (Mod4) — Windows/Super key
- `SHIFT`
- `CTRL`
- `ALT`

## Examples

### Launch application:

```
bind = SUPER, Return, exec, kitty
bind = SUPER, D, exec, rofi -show drun
```

### Window control:

```
bind = SUPER, Q, killactive
bind = SUPER, F, fullscreen
bind = SUPER, Space, togglefloating
```

### Workspaces:

```
bind = SUPER, 1, workspace, 1
bind = SUPER SHIFT, 1, movetoworkspace, 1
```

## Apply Changes

After editing:

```bash
hyprctl reload
```

## Debug

Check active bindings:

```bash
hyprctl binds
```
