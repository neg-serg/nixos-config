# AGENTS usage for hosts/

Scope
- Applies to `hosts/` (machine-specific NixOS configs).
- Repo-wide rules from `/etc/nixos/AGENTS.md` remain in effect.

Guidelines
- Keep changes isolated to the relevant host directory; share logic via modules/profiles/roles instead of copy-pasting between hosts.
- Match the existing split files (`hardware.nix`, `networking.nix`, `services.nix`, `extra.nix`, `virtualisation/`) and keep host glue light.
- Do not embed secrets; pull them from `secrets/` or options.
- Use feature toggles in `modules/features.nix` (or host profiles) rather than ad-hoc host hacks whenever possible.
