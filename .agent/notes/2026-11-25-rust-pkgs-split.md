# 2026-11-25 — the Rust crates moved to their own flake

Status: extracted, published and wired. The gaps at the bottom are deliberate and each names how to
close it.

Repository: <https://github.com/neg-serg/rust-pkgs> (public, branch `main`, initial import
`0897820`). Live checkout: `/home/neg/src/rust-pkgs`.

## What moved out of this tree

| was here                                                                                                                                                                                                                                             | now                                                                                                    |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `packages/{blizzard,dsh-patch,game,hwctl,hypr-focus,hypr-rearrange,local-bin-*,minibbs,music-apply-tags,nixbuild-status,pretty-printer,pwroute,questyle-ctl,renoise-osc,scratchpad-geometry,swayimg-actions,tidalctl,vivaldi-prefs,wineapps,zalgo}/` | repository root, one directory per crate (28 directories, 27 packages — `local-bin-core` is a library) |
| each `default.nix`                                                                                                                                                                                                                                   | `package.nix` (same content; the host calls it by path)                                                |
| `packages/rust-slim.nix`                                                                                                                                                                                                                             | `lib/rust-slim.nix`, exposed as `lib.slim`                                                             |
| `packages/lib/mkMeta.nix` (still here for in-tree packages)                                                                                                                                                                                          | `lib/mkMeta.nix`, a copy the standalone builds need                                                    |
| `packages/Cargo.toml` + `packages/Cargo.lock` (a 7-member workspace whose members all moved)                                                                                                                                                         | gone: each crate carries its own lockfile and builds independently                                     |
| `scripts/dev/bump-version.sh` + `just bump`                                                                                                                                                                                                          | `scripts/bump-version.sh` there; the recipe is gone because no Rust crate is left in this tree         |

`packages/local-bin/` (the shell scripts the `local-bin-*` binaries replaced) stays: it is host
data, not part of the crates.

## How the host consumes it

- `flake.nix`: `rust-pkgs.url = "github:neg-serg/rust-pkgs"`, `inputs.nixpkgs.follows = "nixpkgs"`.
- `packages/overlay.nix`, `packages/overlays/tools.nix`, `packages/overlays/media.nix`:
  `final.callPackage (inputs.rust-pkgs + "/<crate>/package.nix") { }` — **not**
  `packages.<system>.<crate>`. The crates take nixpkgs arguments (`hyprland`, `wineWow64Packages`,
  `sqlite`, `makeWrapper`) and only this flake's package set is the one the system closure already
  contains; building them against the input's private nixpkgs would add second copies of wine or the
  compositor. Calling the package file keeps `callPackage` filling those arguments from here.
- Attribute names did not change, so no module needed an edit: the 67 references in
  `modules/user/nix-maid/cli/local-bin.nix` and every `pkgs.neg.*` consumer still resolve.
- `packages/overlay.nix` now takes the slimming wrapper from the input
  (`inputs.rust-pkgs.lib.slim`), so the binaries keep the full strip + fat LTO they had in-tree.
- `flake/lib.nix` still re-asserts the Rust `pretty-printer` after `neg-pkgs` (its python-era copy
  has no `vid-info`); the path it calls now points into the input.

## Verification done that day

In the new repository: `nix flake lock`, `nix build -L .#all` green — all 27 packages built,
including the wrappers that take `hyprland` (`hypr-rearrange`, `scratchpad-geometry`) and wine
(`wineapps`).

Here: `pkgs.neg.{hwctl,game,tidalctl,local-bin-tools,pretty-printer,wineapps}` and top-level
`pkgs.pwroute` evaluate; `pkgs.neg.<crate>.src` resolves to the crate directory inside the input's
store path (it contains the renamed `package.nix`), i.e. the build really reads the extracted
sources. `just fmt`, `just lint` (18 gates), `just check`, and the `trantor` toplevel build.

## Gaps to fix later

1. **No Nix cache in the new repository's CI.** `nix build -L .#all` compiles every crate on each
   push; the shtoy extraction has the same gap.
1. **`lib/mkMeta.nix` is duplicated** between the two repositories. Deliberate: the package files
   must build standalone there and against this tree's `pkgs.lib` here, and the file is 46 lines.
   Changing the meta convention means changing both copies.
1. **The crates lost their in-tree git history.** The move is one import commit, not
   `git filter-repo`; the old commits still hold it in this repository's history.
1. **Doc comments in the extracted sources still name host paths** (`files/quickshell/...`,
   `files/sources/...`). They describe where the configuration they cooperate with lives, so they
   were not rewritten.
