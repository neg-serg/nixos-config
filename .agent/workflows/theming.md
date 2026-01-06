---
description: Quickshell and Rofi theming
---

# Theming

## Quickshell

### Configuration:

```
files/quickshell/
├── Bar/           # Status bar
├── Theme/         # Theme settings
├── Settings/      # User settings
└── greeter/       # Login greeter
```

### Modify Colors:

Edit `files/quickshell/Theme/panel.jsonc`:

```json
{
  "colors": {
    "primary": "#c1c1ff",
    "surface": "#131318"
  }
}
```

### Reload:

```bash
quickshell --quit && quickshell &
```

## Rofi

### Theme Files:

```
packages/rofi-config/
├── colors.rasi    # Color definitions
├── common.rasi    # Shared styles
├── askpass.rasi   # Password prompt
└── menu-*.rasi    # Menu styles
```

### Modify Theme:

Edit `packages/rofi-config/colors.rasi`:

```css
* {
    primary: #c1c1ff;
    surface: #131318;
    on-surface: #e4e1e9;
}
```

### Test Theme:

```bash
rofi -show drun -theme ~/.config/rofi/config.rasi
```

## Hot Reload

For impurity-enabled configs:

- Changes apply immediately
- No rebuild needed
