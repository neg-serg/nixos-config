# Файлы

Статические файлы конфигурации, связываемые с home через nix-maid.

## Структура

| Директория | Назначение | |------------|------------| | `gui/` | Hyprland, waybar, desktop configs
| | `shell/` | Zsh, bash, environment | | `kitty/` | Kitty terminal | | `nvim/` | Neovim
configuration | | `git/` | Git config and ignore | | `quickshell/` | Status bar and greeter | |
`rofi/` | Rofi scripts and wrappers | | `config/` | Misc app configs | | `wallust/` | Color scheme
generator |

## Использование

Файлы связываются через хелперы nix-maid:

```nix
config.lib.neg.mkHomeFiles {
  ".config/app/config" = { source = ./files/app/config; };
};
```

## См. также

- `files/quickshell/README.md` — конфигурация Quickshell
- `modules/user/nix-maid/` — модули nix-maid
