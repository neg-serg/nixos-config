# AGENTS usage for modules/

Scope

- Applies to the entire `modules/` tree (NixOS modules and nix-maid user config).
- Top-level repo rules from `/etc/nixos/AGENTS.md` still apply.

Guidelines

- Follow the layout in `modules/README.md`: put new modules in the appropriate domain folder — the
  domain's `default.nix` auto-imports sibling `.nix` files and module subdirectories via
  `neg.importDir` (no `modules.nix` registration exists).
- Define new options in `modules/features/<domain>.nix` and refresh option docs
  (`OPTIONS.md`/generated outputs) when behavior changes.
- Reuse existing helpers (`lib.neg.*`, `mkDefault`/`mkForce` patterns) instead of ad-hoc wiring;
  avoid drive-by refactors.
- Per-user systemd units go through `lib/systemd-user.nix`: use `mkUserService` for module-shaped
  `systemd.user.services.<name>` entries (it emits only the fields you pass and routes scheduling
  through the `presets`/`mkUnitFromPresets` table), and `mkUserOneshot` for the login-oneshot shape.
  Do not hand-roll the attrset — the module shape keeps scheduling in one place.
- Prefer feature flags for host-specific tweaks; keep secrets out of modules (source from `secrets/`
  imports instead).
