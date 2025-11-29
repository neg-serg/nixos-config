# AGENTS usage for modules/

Scope
- Applies to the entire `modules/` tree (NixOS modules plus HM glue under `home-manager/`).
- Top-level repo rules from `/etc/nixos/AGENTS.md` still apply.

Guidelines
- Follow the layout in `modules/README.md`: put new modules in the appropriate domain folder and add them to that domain's `modules.nix` (not `default.nix`).
- Define new options in `features.nix` (and `features-data` if needed) and refresh option docs (`OPTIONS.md`/generated outputs) when behavior changes.
- Reuse existing helpers (`lib.neg.*`, `mkDefault`/`mkForce` patterns) instead of ad-hoc wiring; avoid drive-by refactors.
- Prefer feature flags/roles for host-specific tweaks; keep secrets out of modules (source from `secrets/` imports instead).
