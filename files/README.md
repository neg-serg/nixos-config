# Files

Static configuration files linked to user home via nix-maid.

## Structure

| Directory | Purpose | |-----------|---------| | `art/` | Art assets (fun extras) | | `cli/` |
Terminal tools (ghostty, kanata, etc.) | | `config/` | Misc app configs (amfora, dosbox,
rustmission) | | `dosemu/` | DOSBox / dosemu configs | | `fastfetch/` | Fastfetch config assets
(skull) | | `git/` | Git config and ignore | | `gui/` | Hyprland, zellij, swayimg, vicinae configs |
| `kitty/` | Kitty terminal | | `media/` | PipeWire / WirePlumber configs | | `mpv/` | MPV player
configs | | `nvim/` | Neovim configuration | | `obsidian-vault/` | Obsidian vault seed | |
`patches/` | Patch files used by packages | | `quickshell/` | Status bar and greeter | | `rmpc/` |
RMPC music client configs | | `shell/` | Zsh, bash, environment | | `tealdeer/` | Tealdeer (tldr)
config | | `transmission/` | Transmission daemon configs | | `vale/` | Vale prose linter styles | |
`virt/` | Virtualisation configs (libvirt domains) | | `vivaldi/` | Vivaldi browser configs | |
`winapps/` | WinApps (RDP bridge) app configs |

Plus top-level `surfingkeys.js` (hand-written Surfingkeys config, wired via
`packages/overlays/gui.nix`).

`x11/` is a **deletion candidate** (2026-10-19): eight icons from an unpacked X11/conky rice, no
reference from any `.nix`/`.lua`/`.md` and no link into the home config, so nothing of it reaches a
generation. Details and the removal note: `files/x11/DELETION-CANDIDATE.md`.

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
