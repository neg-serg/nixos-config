# Lib

Custom Nix library files, imported via `specialArgs.opts` / `lib/opts.nix` and direct imports.

## Files

- `opts.nix` — option helpers (`mkOpt`, `mkBoolOpt`, `mkStrOpt`, …); consumed via `opts` specialArg
  (see `flake/nixos.nix`) and directly by modules.
- `aliae.nix` — shell alias definitions (`alias`-style helpers for the user's shell).
- `package-checks.nix` — package sanity checks wired into `aliae.nix`.
- `neg-helpers.nix` — structural home-file helpers (`mkHomeFiles`, `mkXdgText`, `mkLocalBin`,
  `linkImpure`); single source for `specialArgs.neg` (flake/nixos.nix) and `flake/checks.nix`.
- `quickshell-wrapper.nix` — Quickshell wrapper helpers (used by
  `modules/user/nix-maid/gui/quickshell.nix`).

Runtime helpers (`mkHomeFiles`, `mkLocalBin`, `mkXdgText`, `systemdUser`, `path`, …) live on
`config.lib.neg` (defined in `flake/nixos.nix` specialArgs + exposed via `modules/core/neg.nix`),
not under `lib/`.

## Repo-root file references

To reference a file by its repo-root-relative path instead of fragile `../../../` chains, use
`config.lib.neg.path` in any module:

```nix
{ config, ... }:
{
  environment.etc."foo/bar".source = config.lib.neg.path "files/foo/bar";
}
```

- `path "files/gui/vicinae-theme.toml"` → absolute path to that file (resolved against
  `options.neg.repoRoot`, which defaults to the flake `self` source).
- Use it for **repo-root** targets only (`files/`, `secrets/`, `lib/`, `packages/…`). Sibling
  imports within one area (e.g. `../scripts/`) stay relative.
- Derivation `src` in `mkDerivation` must remain a real path (string breaks input tracking);
  keep `src = ./relative/…` there.
