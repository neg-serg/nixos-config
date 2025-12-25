# NixOS Configuration

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/neg-serg/nixos-config)
[![NixOS](https://img.shields.io/badge/NixOS-24.11-blue?logo=nixos)](https://nixos.org)
[![Commits](https://img.shields.io/badge/commits-4000+-orange)](https://github.com/neg-serg/nixos-config/commits)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

> **A comprehensive, modular NixOS configuration** focused on performance, developer productivity, and low-latency gaming.

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/neg-serg/nixos-config /etc/nixos
cd /etc/nixos

# Build and switch
sudo nixos-rebuild switch --flake .#telfir

# Or use the helper script (if zcli is enabled)
nh os switch
```

## 📊 Project Statistics

| Metric | Count |
|--------|-------|
| **Module Categories** | 32 |
| **Total Nix Files** | 404 |
| **Custom Packages** | 52 |
| **Total Commits** | 4000+ |
| **Active Hosts** | 1 (telfir) |
| **Archived Server Modules** | 28 |

## 🗂️ Repository Structure

```
nixos-config/
├── flake.nix                    # Flake entry point
├── hosts/                       # Host-specific configurations
│   └── telfir/                  # Primary workstation
├── modules/                     # NixOS system modules
│   ├── features/                # Feature flags & toggles (10 files)
│   ├── cli/                     # CLI tools (11 consolidated files)
│   ├── dev/                     # Development tools & languages
│   ├── gui/                     # GUI applications
│   ├── hardware/                # Hardware configuration
│   ├── media/                   # Media applications
│   ├── servers/                 # Server services
│   │   └── _archive/            # Archived unused modules
│   ├── system/                  # System configuration
│   ├── user/                    # User-level configuration
│   │   └── nix-maid/            # User home configuration
│   │       ├── hyprland/        # Hyprland config (6 modules)
│   │       └── ...
│   └── ...
├── packages/                    # Custom package overlays (52)
├── files/                       # Configuration files
│   ├── gui/hypr/                # Hyprland configs
│   ├── quickshell/              # Quickshell panel
│   └── scripts/                 # Utility scripts
├── scripts/dev/                 # Development & CI scripts
├── docs/                        # Documentation
│   └── manual/                  # User manual
└── .github/workflows/           # CI/CD workflows
```

## 🎯 Key Features

### Performance & Gaming
- **CPU Isolation** for dedicated gaming cores (14,15,30,31)
- **Custom launch scripts** (`game-run`, `gamescope-*`)
- **Low-latency optimizations** throughout the stack
- **VRR support** via Gamescope

### Development Environment
- **Multi-language support:** Rust, C/C++, Haskell, Python
- **AI/LLM tools:** Google Antigravity (optional)
- **IaC:** Terraform/OpenTofu support
- **Container runtime:** Docker/Podman

### Window Management
- **Hyprland** with hy3 plugin (i3-inspired tiling)
- **21 workspaces** with semantic routing
- **6 pyprland scratchpads** for quick access
- **Quickshell** panel for status bar

### Media Stack
- **Jellyfin** media server
- **MPD** + clients (rmpc, ncmpcpp)
- **Transmission** torrent client
- **AI upscaling** support (optional)

## 📚 Module Categories

<details>
<summary><strong>Core Modules (16)</strong></summary>

- **args** - Module arguments & impurity support
- **features** - Feature flags (10 sub-modules)
- **neg** - Custom library helpers
- **profiles** - Service profiles
- **roles** - Role-based configs (homelab, workstation, media, monitoring)

</details>

<details>
<summary><strong>System (8)</strong></summary>

- **boot** - Boot loader configuration
- **hardware** - Hardware-specific settings
- **kernel** - Kernel configuration
- **net** - Networking (VPN, firewall)
- **security** - Security hardening
- **virt** - Virtualization (QEMU, Docker, Podman)

</details>

<details>
<summary><strong>Desktop/GUI (12)</strong></summary>

- **gui** - Hyprland, Wayland, Qt
- **fonts** - Font configuration
- **media** - Audio/video applications
- **quickshell** - Panel configuration
- **theme** - GTK/Qt theming

</details>

<details>
<summary><strong>Development (6)</strong></summary>

- **dev** - Programming languages & tools
- **llm** - LLM integration (Codex, etc.)
- **text** - Text editors & viewers

</details>

<details>
<summary><strong>Web & Communication (4)</strong></summary>

- **web** - Browsers (Floorp, Firefox, Nyxt, Yandex)
- **mail** - Email clients (notmuch, isync)
- **torrent** - Torrent clients

</details>

<details>
<summary><strong>Servers (7 active + 28 archived)</strong></summary>

**Active:**
- adguardhome, avahi, caddy, jellyfin, mpd, nextcloud, openssh

**Archived** (in `_archive/`):
- Media: plex, sonarr, radarr, prowlarr, sabnzbd
- AI: vllm, whisper, open-webui, tts-webui
- Services: gitea, portainer, syncthing, seafile

</details>

## 🔧 Development Workflow

### Local Development

```bash
# Enter development shell
nix develop

# Format all code
just fmt

# Run all checks (format, lint, flake check)
just check

# Build configuration without switching
just build

# Update flake inputs
just update
```

### Git Hooks

Pre-commit hooks automatically format and lint code:

```bash
# Enable hooks
just hooks-enable

# Disable hooks
just hooks-disable
```

### CI/CD

GitHub Actions run on every push:
- Code formatting (alejandra)
- Linting (deadnix, statix)
- NixOS configuration evaluation
- Custom checks (CSS, QML, shell scripts)

## 🎨 Customization

### Feature Flags

Configure features in `hosts/telfir/services.nix`:

```nix
features = {
  gui.enable = true;
  gui.hy3.enable = true;
  dev.rust.enable = true;
  web.floorp.enable = true;
  # ... many more options
};
```

See [`modules/features/`](modules/features/) for all available options.

### Profiles

- **`full`** (default): All features enabled
- **`lite`**: Minimal feature set for lightweight systems

### Roles

- **`workstation`**: Desktop-first setup with performance optimizations
- **`homelab`**: Self-hosting services (AdGuard, Nextcloud, etc.)
- **`media`**: Media server (Jellyfin, MPD)
- **`monitoring`**: System monitoring (netdata, sysstat)

## 📖 Documentation

- **[User Manual](docs/manual/manual.en.md)** - Comprehensive guide
- **[Walkthrough](https://github.com/neg-serg/nixos-config/tree/master/.gemini)** - Recent improvements
- **[Package Annotations](modules/)** - Inline comments for all packages

## 🛠️ Custom Packages

This configuration includes **52 custom packages** in the overlay:

**Notable packages:**
- `game-run` - CPU isolation wrapper for games
- `gamescope-*` - Gamescope launchers with presets
- `rmpc` - Modern MPD client (Rust)
- `tewi` - Transmission TUI
- `two_percent` - Optimized fuzzy finder
- `duf` - Better df with plain style
- `comma` - Nix ,command wrapper
- `pretty_printer` - CLI formatting utility

See [`packages/`](packages/) for the full list.

## 🎮 Gaming Setup

### CPU Isolation

This configuration reserves CPUs 14,15,30,31 exclusively for gaming, preventing system services from interrupting game performance.

### Launch Wrappers

```bash
# Basic CPU pinning
game-run %command%

# With Gamescope (VRR + adaptive sync)
game-run gamescope -f --adaptive-sync -- %command%

# Performance preset
gamescope-perf %command%

# Quality preset
gamescope-quality %command%

# HDR support
gamescope-hdr %command%
```

### Environment Variables

- `GAME_PIN_CPUSET`: Override CPU set for specific game
- `GAME_RUN_USE_GAMEMODE`: Enable/disable gamemode
- `MANGOHUD`: Enable performance overlay

## 🌐 Hyprland Configuration

**21 Workspaces:**
- 𐌰:term, 𐌱:web, 𐌲:dev, 𐌸:games, 𐌳:doc, 𐌴:draw, 𐌵:vid
- 𐌶:obs, 𐌷:pic, 𐌹:sys, 𐌺:vm, 𐌻:wine, 𐌼:patchbay
- 𐌽:daw, 𐌾:dw, 𐌿:keyboard, 𐍀:im, 𐍁:remote
- Ⲣ:notes, 𐍅:winboat (floating), 𐍇:antigravity

**6 Scratchpads:**
- `im` - Telegram
- `discord` - Vesktop
- `music` - RMPC
- `torrment` - Tewi
- `teardown` - Btop
- `mixer` - Pwvucontrol

## 🤝 Contributing

This is a personal configuration, but contributions are welcome:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `just check` to verify
5. Submit a pull request

## 📝 License

This configuration is available under the MIT License.

## 🙏 Acknowledgments

- [NixOS](https://nixos.org) - The reproducible Linux distribution
- [Hyprland](https://hyprland.org) - Dynamic tiling Wayland compositor
- [Home Manager](https://github.com/nix-community/home-manager) - User environment management
- [nix-community](https://github.com/nix-community) - Various Nix tools and libraries

---

**Last Updated:** December 2025 • **Version:** 24.11 • **Commits:** 4000+
