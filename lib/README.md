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

Runtime helpers (`mkHomeFiles`, `mkLocalBin`, `mkXdgText`, `systemdUser`, …) live on
`config.lib.neg` (defined in `flake/nixos.nix` specialArgs + exposed via `modules/core/neg.nix`),
not under `lib/`.
