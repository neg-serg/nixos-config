______________________________________________________________________

---
name: nixos-build
description: "Build and switch NixOS configurations with validation. Use when building, switching, testing, or deploying NixOS config changes."
---

# NixOS Build

Build, switch, and validate NixOS configurations for this repository.

## Quick Build & Switch

```bash
# Full switch (default host: odin)
sudo nixos-rebuild switch --flake .#odin

# Build only (no switch)
nixos-rebuild build --flake .#odin

# With nh (fast alternative)
nh os switch
```

## Validate Before Build

```bash
# Format check
just fmt

# Full check suite (format + lint + eval)
just check
```

## Rollback

```bash
# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# List generations
sudo nix-env --list-generations -p /nix/var/nix/profiles/system

# Rollback to specific generation
sudo nixos-rebuild switch --rollback <generation-number>
```

## Update Flake Inputs

```bash
# Update all inputs
just update

# Update single input
nix flake lock --update-input nixpkgs

# Update flake.lock without updating inputs
nix flake lock
```

## Garbage Collection

```bash
# Delete old generations
sudo nix-collect-garbage -d
nix-collect-garbage -d

# Show store usage
nix store du
```
