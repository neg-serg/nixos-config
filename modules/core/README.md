# Core Module

This module provides core configuration options and library functions for the entire NixOS
configuration.

### Contents

- `neg.nix` — Defines global options under `neg.*` namespace and exposes helper functions via
  `lib.neg`

### Options

| Option | Type | Description |
|--------|------|-------------|
| `neg.repoRoot` | string | Path to the configuration repository root (default: `/etc/nixos`) |
| `neg.rofi.package` | package | The rofi package to use system-wide |
