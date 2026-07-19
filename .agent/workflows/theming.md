______________________________________________________________________

## description: Quickshell theming

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

## Hot Reload

For impurity-enabled configs:

- Changes apply immediately
- No rebuild needed
