# Custom Libraries (`modules/lib`)

This directory contains a set of custom Nix libraries designed to simplify, modularize, and add powerful abstractions to the home-manager configuration.

The primary entry point is `neg.nix`, which aggregates helpers from the other files in this directory and makes them available to all modules under the `lib.neg` attribute.

## Core Files

### `neg.nix`

This is the main aggregator file for the custom library. It imports functions from `helpers.nix`, `systemd-user.nix`, and others, and exposes them as a single, unified library accessible via `lib.neg` throughout the configuration. It also defines a few high-level custom options for things like Rofi and a custom Quickshell wrapper.

### `paths.nix`

This file defines several key path options (`neg.hmConfigRoot`, `neg.repoRoot`, `neg.packagesRoot`). Centralizing these paths makes the entire configuration more portable and easier to maintain, as file paths are not hard-coded in individual modules.

## Helper Libraries

### `helpers.nix` - General Helpers

This file is a collection of general-purpose functions.

-   `mkEnabledList` (aliased as `mkPackagesFromGroups`): A powerful function that takes a set of feature flags and a corresponding set of package groups to produce a final list of packages. This is key to the modularity of the system.
-   **Nix Expression Helpers**: A set of convenience functions like `mkWhen`, `mkUnless`, and `mkBool` to make conditional Nix expressions more readable.
-   **Activation DAG Helpers**: A suite of advanced functions (`mkEnsureRealDir`, `mkRemoveIfSymlink`, `mkEnsureAbsent`, etc.) that leverage home-manager's activation `dag` (Directed Acyclic Graph). These functions allow for precise filesystem manipulations (e.g., creating directories, removing old files) at specific stages of the activation process, ensuring the system is in a clean state before home-manager creates its symlinks.

### `xdg-helpers.nix` - XDG Helpers

This library provides a clean API for creating files that adhere to the XDG Base Directory Specification. This avoids hard-coding paths like `~/.config` or `~/.local/share`.

-   **File Creation**: Functions like `mkXdgText`, `mkXdgSource`, `mkXdgDataText`, and `mkXdgCacheText` allow for declaratively creating files in the correct XDG locations (`$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `$XDG_CACHE_HOME`).
-   **Structured Data Helpers**: Convenience functions like `mkXdgConfigJson` and `mkXdgConfigToml` simplify the creation of structured configuration files from Nix attribute sets.

### `systemd-user.nix` - Systemd User Unit Helpers

This library provides high-level abstractions for creating user-level systemd units (services, timers, and sockets).

-   **Presets**: Defines a collection of common unit settings (e.g., `graphical` for GUI apps, `timers` for timer-activated jobs).
-   **Unit Constructors**: Functions like `mkSimpleService`, `mkSimpleTimer`, and `mkSimpleSocket` use these presets to make defining new user units simple and declarative, hiding much of the boilerplate.
