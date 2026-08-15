# Modules

Dendritic NixOS module tree. Each domain lives in its own directory with a `default.nix` that
auto-imports all sibling `.nix` files and subdirectories (via `builtins.readDir`).

```
modules/
├── default.nix          # top-level: imports all domains (manual list with domainFilter)
├── features/            # feature flags (auto-import)
├── profiles/            # host profiles (auto-import)
└── <domain>/            # one directory per domain
    ├── default.nix      # auto-imports everything below
    ├── *.nix            # flat module files
    └── <sub>/           # subdirectory → resolved to <sub>/default.nix
```

## Domains

| Domain          | Purpose                                                                                         |
| --------------- | ----------------------------------------------------------------------------------------------- |
| `appimage`      | AppImage integration — binfmt registration, FHS compat                                          |
| `apps`          | Application-specific configs (Obsidian, etc.)                                                   |
| `cli`           | CLI tools — file ops, text processing, networking, compression                                  |
| `core`          | Core helpers: `lib.neg`, global `neg.*` options                                                 |
| `dev`           | Development — Android, C/C++, Python, editor, git, security research                            |
| `documentation` | Man pages, info pages, doc viewers                                                              |
| `emulators`     | Console/system emulators (RetroArch, standalone)                                                |
| `features`      | Feature flags (`features.gui.enable`, `features.dev.enable`, …) — auto-import                   |
| `flatpak`       | Flatpak integration with overrides and env vars                                                 |
| `fonts`         | Fonts — Iosevka (Nerd Font), Pango, fontconfig defaults                                         |
| `fun`           | Terminal toys, ASCII art, screensavers                                                          |
| `games`         | System-level gaming config (controllers, etc.)                                                  |
| `hardware`      | Hardware — GPU (AMD/NVIDIA), audio, cooling, QMK, udev, USB automount                           |
| `lib`           | Shared helper modules (systemd-user presets); runtime helpers live in `lib/` + `config.lib.neg` |
| `llm`           | Local LLM — Ollama (ROCm on RX 9070 XT), CLI tools. Models at `/zero/llm/`                      |
| `media`         | Audio (PipeWire, MPD), images, video (FFmpeg, VapourSynth, AI upscaling)                        |
| `monitoring`    | System monitoring — Alertmanager, sysstat, vnstat                                               |
| `nix`           | Nix daemon — caches, GC, nix-ld, Hyprland, settings                                             |
| `profiles`      | Host profiles (desktop, gaming, dev) — auto-import                                              |
| `secrets`       | sops-nix secrets — pass, yubikey, pkgs                                                          |
| `security`      | Hardening — AppArmor, sudo, PAM limits, polkit, pcscd                                           |
| `servers`       | Services — AdGuard Home, Avahi, Geoclue, MPD, OpenSSH, Samba, Unbound                           |
| `shell`         | Shell — Zsh with plugins, Oh My Posh, aliases, env vars                                         |
| `system`        | Core system — boot (Limine), kernel, networking, systemd, users, virtualisation                 |
| `text`          | Text processing — editors, PDF tools, converters                                                |
| `tools`         | Miscellaneous — nix-output-monitor (Nerd Font icons), custom wraps                              |
| `torrent`       | BitTorrent — Transmission daemon, rustmission, stig TUI                                         |
| `user`          | User-level via nix-maid — session (Hyprland), apps, CLI, games, GUI, web                        |

## Key sub-structures

### `user/nix-maid/`

User config management — `apps/`, `cli/`, `gui/`, `web/`, `sys/`, `fun/`.

### `system/`

- `boot/` — bootloader, initrd
- `kernel/` — kernel config, params, modules
- `net/` — NetworkManager, firewall, VPN (WireGuard, sing-box, AmneziaWG)
- `profiles/` — systemd service profiles (Aliases, AdGuard rewrite)
- `systemd/` — systemd unit overrides
- `vm/definitions.nix` — libvirt domain XML (gentoo, nixos, win11)

### `dev/`

- `android/`, `benchmarks/`, `editor/`, `gcc/`, `gdb/`, `git/`, `java/`, `python/`, `unreal/`,
  `pkgs/`
- Security research (forensics, pentest, reverse engineering)

### `hardware/`

- `audio/`, `cpu/`, `input/`, `io/`, `qmk/`, `udev-rules/`, `video/`, `webcam/`

### `media/`

- `audio/` — PipeWire (low-latency), MPD
- `images/` — viewers, editors
- `scripts/` — media processing scripts (not imported as module)

## Adding a module

1. Create a `.nix` file or subdirectory with `default.nix` inside the relevant domain.
1. That's it — the domain's `default.nix` auto-imports everything via `readDir`.
1. For a new top-level domain, add it to `modules/default.nix`.

## Feature flags

Enable/disable domains per host:

```nix
features = {
  gui.enable = true;
  dev.enable = true;
  cli.enable = true;
  games.enable = false;
};
```

Flags defined in `features/` (auto-imported). Each domain's config is gated by its feature flag via
`lib.mkIf`.
