# Repository Overview

NixOS configuration for `trantor` (flake: NixOS + nix-maid) with user-level management under
`modules/user/nix-maid/`. This file is the map: where things live, how to rebuild, and where the
details are documented. Deep material lives in howtos and runbooks, not here.

## Layout

- `flake.nix`, `flake/` — entry point and helpers (`nixos.nix` with `trantorDomains`, `checks.nix`).
- `modules/` — system modules by domain (`features/`, `cli/`, `dev/`, `servers/`, `system/`,
  `user/`).
- `hosts/trantor/` — host-specific configuration (services, hardware, networking, policy).
- `packages/` — local derivations, CLI wrappers, overlays; `files/` — static configs linked by
  nix-maid.
- `lib/`, `secrets/`, `scripts/` — shared helpers, SOPS secrets, dev scripts.
- `docs/` — `runbook-*.md` (operations, index in `docs/runbook-index.md`), `howto/` (topic howtos,
  index in `docs/howto/index.md`), this overview.
- `.agent/` — agent scaffolding: `workflows/`, `plans/` (open work), `upstream-fix/`.
- Ignored, never committed: `result` (last build), `nix/`, `viz/`, `.agent/tmp*/`.

## Quick start

### System

- Rebuild as the user: `nh os switch /etc/nixos#trantor --option substitute false`.
- Plain `nixos-rebuild` with a password prompt: `just switch-sudo`.
- Agent rollout without a password: build the closure, then
  `just agent-switch "$(readlink -f result)"` (the root-owned unit re-checks the tree first).
- Format / lint / full check: `just fmt`, `just lint`, `just check`; git hooks: `just hooks-enable`.
- `cache.nixos.org` is unreliable from this region: every nix invocation passes
  `--option substitute false`.
- `nom`/`nh` carry a local patch for Determinate Nix's activity type `10113`
  (`modules/tools/default.nix`, upstream
  [PR #321](https://github.com/maralorn/nix-output-monitor/pull/321)); drop it once a release ships
  the fix. Without it `nh os switch` dies with `invalid activity type: 10113`.

### User configuration

1. Nix with flakes enabled (`experimental-features = nix-command flakes`); `just` optional.
1. User modules live under `modules/user/nix-maid/` (`apps/`, `cli/`, `gui/`, `sys/`, `fun/`,
   `web/`) and apply during `nixos-rebuild switch` — `nixos-rebuild build --flake .#<host>` builds
   without switching.
1. Feature flags: primary toggle `features.profiles` (`["desktop" "dev" "gaming"]` on trantor),
   definitions in `modules/features/`, overview in `OPTIONS.md`.

## Documentation map

| Need                                                              | Read                                               |
| ----------------------------------------------------------------- | -------------------------------------------------- |
| Operational steps                                                 | `docs/runbook-index.md`                            |
| Topic howtos                                                      | `docs/howto/index.md`                              |
| Feature flags and their composition                               | `OPTIONS.md`                                       |
| Coding style, module patterns, systemd-user helpers, commit rules | `docs/howto/repo-conventions.md`                   |
| Adding a module / flag / package / secret, rebuild recipes        | `.agent/workflows/`, `docs/howto/agent-recipes.md` |
| Open work per direction                                           | `.agent/plans/`                                    |
| Prepared upstream patch series                                    | `.agent/upstream-fix/README.md`                    |
| Repo-wide agent rules                                             | `AGENTS.md`                                        |

## Conventions

- Nix style, module structure, activation helpers and commit format (`[scope] subject`) are in
  `docs/howto/repo-conventions.md`; the enforced rules also live in `AGENTS.md` and the git hooks.
- Secrets stay SOPS-encrypted under `secrets/` (wiring: `docs/runbook-vaultix-migration.md`); age
  keys live outside the repo in `~/.config/sops/age/keys.txt`.
- Evaluation output stays quiet: see the noise policy below.
- Hyprland pins, plugin patches and session notes: the header of
  `modules/user/nix-maid/hyprland/main.nix`.

## Third-Party Components

Keep this manifest updated whenever vendored sources change so that licensing remains clear.

| Component           | Source                                                                                     | Revision                                   | License                        | Notes                                                                                                     |
| ------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------ | ------------------------------ | --------------------------------------------------------------------------------------------------------- |
| kitty-kitten-search | [github.com/trygveaa/kitty-kitten-search](https://github.com/trygveaa/kitty-kitten-search) | `992c1f3d220dc3e1ae18a24b15fcaf47f4e61ff8` | *No license declared upstream* | Provides `search.py` / `scroll_mark.py` kittens for Kitty. Verify licensing before distributing binaries. |

## Evaluation Noise Policy

- No evaluation-time warnings or traces. Keep builds and switches quiet.
- Do not use `warnings = [ ... ]`, `builtins.trace`, or `lib.warn` in modules.
- If a package/feature is unavailable, silently skip or guard with a flag. Document behavior in the
  module header or a howto instead of emitting warnings.
- Use assertions only for truly fatal misconfigurations, and phrase them concisely.

## Open Tasks

Open work lives in `.agent/plans/` (one file per direction); `docs/howto/index.md` points to the
howto that describes each area.
