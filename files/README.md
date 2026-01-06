# Files

Static configuration files linked to user home via nix-maid.

## Structure

| Directory | Purpose |
|-----------|---------|
| `gui/` | Hyprland, waybar, desktop configs |
| `shell/` | Zsh, bash, environment |
| `kitty/` | Kitty terminal |
| `nvim/` | Neovim configuration |
| `git/` | Git config and ignore |
| `quickshell/` | Status bar and greeter |
| `rofi/` | Rofi scripts and wrappers |
| `config/` | Misc app configs |
| `wallust/` | Color scheme generator |

## Usage

Files are linked via nix-maid helpers:

```nix
config.lib.neg.mkHomeFiles {
  ".config/app/config" = { source = ./files/app/config; };
};
```

## See Also

- `files/quickshell/README.md` — Quickshell configuration
- `modules/user/nix-maid/` — nix-maid modules
