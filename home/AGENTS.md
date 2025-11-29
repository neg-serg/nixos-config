# AGENTS usage for home/

Scope
- Applies to the Home Manager tree under `home/`.
- Top-level repo rules still apply; nested AGENTS (e.g., `home/files/quickshell/AGENTS.md`) take precedence in their subdirectories.

Guidelines
- Extend feature flags in `home/modules/features.nix`; adjust defaults in `home/home.nix` only when necessary.
- Compose configs via `home/profiles` and domain modules in `home/modules/`; avoid wiring modules directly in `home/home.nix`.
- Read `home/modules/README.md` for the domain map and helpers; prefer `lib/neg` utilities already provided there.
- Route secrets through the `home/secrets` import instead of hard-coding paths or values.
