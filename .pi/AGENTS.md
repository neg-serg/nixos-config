# NixOS Configuration (/etc/nixos)

Host: telfir — Primary workstation (AMD Ryzen 9 7950X3D, Radeon RX 7900 XTX)

## Quick Commands

- **Build & switch**: `sudo nixos-rebuild switch --flake .#telfir`
- **Quick switch**: `nh os switch`
- **Build only**: `nixos-rebuild build --flake .#telfir`
- **Format all**: `just fmt`
- **Full check**: `just check` (format + lint + build)
- **Update flake**: `just update`
- **GC**: `sudo nix-collect-garbage -d && nix-collect-garbage -d`

## Commit Style

```
[scope] Short imperative description without period

Examples:
  [media/audio] Add TidalCycles live-coding stack
  [hosts/telfir] Tune cooling profile
  [dev/pkgs] Fix herdr package access
```

Scopes: nixpkgs, core/modules, flake/eval, hosts/telfir, dev/*, cli/*, hardware/*, media/*, docs, etc.

## Project Structure

- `flake.nix` — Entry point (NixOS + home-manager)
- `modules/` — System modules (features/, cli/, dev/, servers/, etc.)
- `hosts/telfir/` — Host-specific config (services.nix, hardware.nix, networking.nix...)
- `packages/` — Custom overlays and packages
- `secrets/` — SOPS-encrypted secrets
- `files/` — Config files (Hyprland, Quickshell panel, scripts)

## Feature Flags

Most components are controlled via feature flags in `modules/features/`:

```nix
features.dev.ai.opencode.enable = true;
features.dev.ai.pi.enable = true;
features.cli.broot.enable = true;
```

## Rules

- Use `pkgs.*` with short comments in package lists
- Prefer existing module structure, no drive-by refactors
- Keep changes minimal and focused
- Use `just fmt` before committing
- Secrets go to `secrets/` with SOPS, never in plaintext
- Update docs under `docs/` when changing behavior
