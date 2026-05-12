# Features Module

Feature flags for conditional system configuration.

## Usage

```nix
features = {
  gui.enable = true;      # Enable GUI
  dev.enable = true;      # Enable dev tools
  cli.enable = true;      # Enable CLI
  games.enable = true;    # Enable gaming
};
```

## Purpose

Allows selective enabling of system components based on host role.
