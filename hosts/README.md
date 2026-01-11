# Hosts

Machine-specific configurations.

## Available Hosts

| Host | Description |
|------|-------------|
| `telfir` | Primary workstation |

## Structure

Each host directory contains:

- `default.nix` — Entry point
- `hardware.nix` — Hardware configuration
- `networking.nix` — Network settings
- `services.nix` — Host-specific services

## Adding a Host

1. Create `hosts/new-host/default.nix`
1. Add to `flake.nix` in `nixosConfigurations`
1. Build: `sudo nixos-rebuild switch --flake .#new-host`
