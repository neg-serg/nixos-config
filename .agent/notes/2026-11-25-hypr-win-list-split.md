# 2026-11-25 — hypr-win-list moved to its own flake

Status: extracted, published and wired. The gaps at the bottom are deliberate and each names how to
close it.

Repository: <https://github.com/neg-serg/hypr-win-list> (public, branch `main`, initial import
`ff8731f`). Live checkout: `/home/neg/src/hypr-win-list`.

## What moved out of this tree

| was here                                             | now                                                                                                   |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `packages/hypr-win-list/{Cargo.toml,Cargo.lock,src}` | repository root                                                                                       |
| `packages/hypr-win-list/default.nix`                 | `package.nix` there (plain `meta`, GitHub homepage, `platforms = lib.platforms.linux`)                |
| —                                                    | `flake.nix`, `flake.lock`, `LICENSE`, `.gitignore`, `.github/workflows/ci.yml`, `README.md`, `tests/` |

The host glue stays here: `modules/user/nix-maid/hyprland/services/compositor-helpers.nix` keeps
`pkgs.neg.hypr-win-list` in the package list and the Hyprland binding that runs it.

Two packaging details changed with the move. The port header (`Rust port of hypr-win-list.py`) went
away — the Python tree is long gone — and the crate gained `HYPR_WIN_LIST_VICINAE` next to
`HYPR_WIN_LIST_HYPRCTL`, so the flake check can point both binaries at stubs. Note the parameter
name: it is `withRuntimePath`, not `wrap`, because `callPackage` fills every function argument whose
name exists in the package set (defaults included) and nixpkgs has a Go tool named `wrap` — the
default would silently never apply.

## How the host consumes it

- `flake.nix`: `hypr-win-list.url = "github:neg-serg/hypr-win-list"`,
  `inputs.nixpkgs.follows = "nixpkgs"`.
- `packages/overlays/tools.nix`: `pkgs.neg.hypr-win-list` is the input's `packages.<system>.default`
  with `override { inherit (final) hyprland vicinae; }`. Verified: the wrapper's PATH carries the
  host's patched vicinae and its hyprland, not the input's nixpkgs copies — without the override the
  closure would gain a second Qt launcher and a second compositor.
- The name left `rustNegNames` together with its `neg` chunk entry in `packages/overlay.nix`: the
  chunk lookup `chunks.${name}` throws on a missing attribute, so the two move as one. An extracted
  package is no longer `rustSlim`-wrapped here, the same tradeoff as `mpd-voice`.
- README statistic: Nix Files 589 → 588.

## Verification done that day

In the new repository: `nix flake lock`, `nix flake check -L` green — the `picker` check serves
three documents from `tests/fixtures/` through a stub `hyprctl`, answers the picker from
`tests/stubs/`, and asserts the two eligible lines (special workspace, unmapped, focused and
control-character windows hidden) plus the dispatched focus call. `nix build .#default` produced the
wrapped binary; `rustfmt --check` clean.

Here: `nix build .#nixosConfigurations.trantor.pkgs.neg.hypr-win-list` through the new input,
`just fmt`, `just lint`.

## Gaps to fix later

1. **No `#[test]` items.** The flake check exercises the pipeline end to end through stubs, not the
   individual parser functions (`clip`, `workspace_label`, `glyph`, the JSON reader).
1. **CI has no Nix cache.** `nix build .#default` pulls the vicinae/hyprland closure from
   cache.nixos.org on every push; fine while the crate is this small, worth a cache otherwise.
1. **The default `nixpkgs` pin copies this host's rev.** A consumer that does not pass
   `inputs.nixpkgs.follows` gets that snapshot; the host does pass it.

## Commits

- `ff8731f` — initial import (crate + packaging + docs + CI + fixture check).
- This tree: the extraction commit (input, overlay entry, package removal, README statistic).
