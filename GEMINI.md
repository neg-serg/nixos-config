# Gemini Code Assistant Context

This document provides context for the AI assistant to understand and effectively work with this NixOS and Home Manager configuration repository.

## Project Overview

This is a comprehensive NixOS and Home Manager configuration managed as a Nix Flake. It defines the configurations for multiple hosts and users, with a strong emphasis on modularity, reproducibility, and developer tooling.

The repository is structured to separate system-level concerns (NixOS modules) from user-level configurations (Home Manager), although they are tightly integrated. It also includes a custom package overlay, extensive documentation, and a suite of development and linting tools. Two of the most specialized features of this repository are its advanced gaming performance tuning and its structured approach to managing multiple hosts.

## Key Files and Directories

*   `flake.nix`: The entry point for the entire configuration. It defines the flake's inputs (dependencies), outputs (packages, NixOS systems, Home Manager profiles), and sets up the overall structure.
*   `modules/`: Contains the core NixOS modules that define the system's functionality. This is where most of the system-wide configuration logic resides.
*   `hosts/`: Contains host-specific configurations. Each subdirectory corresponds to a machine managed by this repository (e.g., `telfir`).
*   `packages/`: A Nix overlay containing custom packages and derivations that are not available in the main Nixpkgs repository.
*   `lib/`: Custom library functions written in Nix to simplify and abstract common patterns within the configuration.
*   `Justfile`: Defines a set of commands for common development tasks like formatting, linting, building, and deploying configurations. This is the primary interface for managing the repository.
*   `docs/manual/manual.en.md`: The main documentation for the repository, providing a detailed overview of the structure, conventions, and workflows.
*   `secrets/`: Contains secrets encrypted with `sops`. These are decrypted at build time using `sops-nix`.

## Building and Applying Configurations

### NixOS

To build and switch to a new NixOS generation for a specific host:

```bash
sudo nixos-rebuild switch --flake .#<host_name>
```

Replace `<host_name>` with the name of a host defined in the `hosts/` directory (e.g., `telfir`).

### Home Manager

To build and switch to a new Home Manager generation for the `neg` user:

```bash
just hm-neg
```

This is an alias for `home-manager switch --flake .#neg`.

## Development Workflow

This repository has a well-defined development workflow enforced by tooling.

### Development Shell

To enter a development shell with all the necessary tools (linters, formatters, etc.) available:

```bash
nix develop
```

### Formatting and Linting

*   **Format all code:** `just fmt`
*   **Run all checks:** `just check` (includes formatting, linting, and flake checks)
*   **Run only linters:** `just lint`

### Git Hooks

The repository includes pre-commit hooks to automatically format and lint code. To enable them: `just hooks-enable`.

## Host Management

Adding a new host involves creating a new directory and defining its specific configuration by applying shared roles and profiles.

### Adding a New Host

1.  **Create a directory** for the new host under `hosts/`. For example, `hosts/new-machine/`.
2.  **Create a `default.nix`** inside the new directory. This file should import other modules for the host, such as `hardware.nix`, `networking.nix`, and `services.nix`.
    ```nix
    # hosts/new-machine/default.nix
    {
      imports = [
        ./hardware.nix
        ./networking.nix
        ./services.nix
      ];
    }
    ```
3.  **Define host-specifics** in the imported files. The primary way to configure a host is by enabling `roles` and `profiles`.
    *   **Roles** (`roles.*`): Enable broad configuration bundles like `workstation` or `homelab`.
    *   **Profiles** (`profiles.*`): Enable more granular feature sets like `performance` or `security`.
    *   **Services** (`profiles.services.*`): Toggle specific major services like `nextcloud` or `adguardhome`.

    **Example `services.nix` for a new host:**
    ```nix
    { lib, ... }: {
      # Enable the workstation and homelab roles
      roles = {
        workstation.enable = true;
        homelab.enable = true;
      };

      # Disable a specific service from a role for this host
      profiles.services.nextcloud.enable = false;

      # Add host-specific settings
      services.syncthing.settings.devices."my-phone" = { id = "AAAA-BBBB-..."; };
    }
    ```
4.  **Add the host to `flake.nix`**: In the `nixosConfigurations` output, add an entry for `new-machine` that points to its `default.nix`.
5.  **Build the new host's configuration**: `sudo nixos-rebuild switch --flake .#new-machine`.

## Performance and Gaming

This configuration has a highly specialized setup for low-latency gaming, centered around CPU isolation and custom launch scripts.

### CPU Isolation

*   The primary host `telfir` reserves a specific set of CPU cores (`14,15,30,31`) exclusively for gaming. System services are kept on other "housekeeping" CPUs to prevent interruptions.
*   The `game-run` script is the core of this feature. It launches any command within a dedicated systemd scope that is pinned to the isolated CPU cores.

### Launching Games

The preferred way to launch games is by wrapping the game's command with a helper script in the Steam launch options or on the command line.

*   **Basic (CPU pinning only):**
    ```bash
    game-run %command%
    ```
*   **With Gamescope (for VRR and better frame pacing):**
    ```bash
    game-run gamescope -f --adaptive-sync -- %command%
    ```
*   **Using Presets:** There are several wrappers for `gamescope` with different settings:
    *   `gamescope-perf`: Prioritizes performance.
    *   `gamescope-quality`: Prioritizes visual quality.
    *   `gamescope-hdr`: Enables HDR.

### Key Environment Variables

The gaming launchers can be customized with environment variables:

*   `GAME_PIN_CPUSET`: Overrides the default set of isolated CPU cores for a specific game (e.g., `GAME_PIN_CPUSET=12-15,28-31`).
*   `GAME_RUN_USE_GAMEMODE`: Set to `0` to disable `gamemoderun` for a specific launch.
*   `MANGOHUD`: Set to `1` to enable the MangoHud overlay.

**Example Steam Launch Option (Competitive FPS):**
```
GAME_PIN_CPUSET=14,15,30,31 MANGOHUD=1 game-run gamescope -f --adaptive-sync -- %command%
```

## Coding Conventions and Best Practices

*   **Feature Flags**: Configuration is heavily controlled by feature flags defined in `modules/features.nix`. Use `features.*` options to toggle functionality.
*   **Custom Library**: Use helpers from `config.lib.neg.*` for conditional logic (`mkWhen`), managing XDG files (`mkXdgText`), and creating local scripts (`mkLocalBin`).
*   **Systemd User Services**: Use `config.lib.neg.systemdUser.mkUnitFromPresets` to create systemd user units with consistent dependencies.
*   **Commit Messages**: Must follow the `[scope] summary` format.
*   **Comments**: All code comments must be written in English.

## Custom Packages

1.  Create a directory for your package under `packages/`.
2.  Add a `default.nix` file with the package derivation.
3.  Add the package to the overlay in `packages/overlay.nix`.
4.  Reference the package via `pkgs.<your-package-name>`.
