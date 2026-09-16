# Lib

Custom Nix library files, imported via `specialArgs.opts` / `lib/opts.nix` and direct imports.

## Files

- `opts.nix` — option helpers (`mkOpt`, `mkBoolOpt`, `mkStrOpt`, …); consumed via `opts` specialArg
  (see `flake/nixos.nix`) and directly by modules.
- `neg-helpers.nix` — structural helpers: home-file helpers (`mkHomeFiles`, `mkXdgText`,
  `mkLocalBin`, `linkImpure`) and `importDir` (directory auto-import for every module aggregator);
  single source for `specialArgs.neg` (flake/nixos.nix) and `flake/checks.nix`; also re-exports
  `ruKeys` from `ru-keys.nix`.
- `systemd-user.nix` — systemd user unit helpers: `mkUnitFromPresets` plus the module-shaped
  `mkUserService` / `mkUserOneshot` / `mkUserActivation`; the legacy `mkSimple*` helpers were
  removed.
- `aliae.nix` — shell alias definitions (`alias`-style helpers for the user's shell); imports
  `package-checks.nix` to skip aliases whose packages are missing.
- `package-checks.nix` — package availability checks (`hasRg`, `hasNmap`, `hasCurl`, …) for the
  alias generators.
- `fzf-opts-tests.nix` — eval-only assertions over `neg-helpers.nix`'s `hasFzfHashComment`; wired
  into `flake/checks.nix` as the `fzf-opts-guard` check.
- `ru-keys.nix` — single source of truth for the RU-layout hotkey problem: latin key → the char the
  ru layout produces, and every per-app duplicate bind is generated from this table. Exposed as
  `neg.ruKeys`; mechanics in `docs/howto/hotkeys-ru-layout.md`.
- `ru-keys-tests.nix` — eval-only assertions over `ru-keys.nix` (neovim langmap golden, table
  parity); wired into `flake/checks.nix` as the `ru-keys` check.
- `caches.nix` — shared binary-cache `trusted-public-keys` (official cache plus community mirrors);
  imported by `modules/nix/settings.nix`.
- `python-packages.nix` — shared Python package list; single source for the system Python env
  (`modules/dev/python/pkgs.nix`) and the Python devshell (`flake/devshells/python.nix`).
- `quickshell-wrapper.nix` — Quickshell wrapper helpers (used by
  `modules/user/nix-maid/gui/quickshell.nix`).
- `quickshell-wrapper-install.sh` — install-phase template read by `quickshell-wrapper.nix`
  (`builtins.readFile`); builds the wrapped `qs` binary with the Qt/QML import paths, theme data and
  `QT_QPA_PLATFORM=wayland`.

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

- `path "files/gui/vicinae-theme.toml"` → a real path to that file (resolved against
  `options.neg.repoRoot`, a path literal injected via specialArgs from `flake/nixos.nix`). Because
  the result is a path (not a string), Nix copies the file into the store and tracks it as a closure
  dependency — the same behavior as the old relative `./../../` references. Do not replace `path`
  with a plain string: strings are not added to derivation closures and their files can be
  garbage-collected.
- `pathExists "…"` — like `builtins.pathExists`, but repo-root-relative (no error when missing); use
  it for optional files.
- Use `path` for **repo-root** targets only (`files/`, `secrets/`, `lib/`, `packages/…`). Sibling
  imports within one area (e.g. `../scripts/`) stay relative.
- Derivation `src` in `mkDerivation` must remain a real path (string breaks input tracking); keep
  `src = ./relative/…` there.
