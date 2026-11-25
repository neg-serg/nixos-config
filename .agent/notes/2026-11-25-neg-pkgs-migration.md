# 2026-11-25 — 35 packages moved to nixos-pkgs

Status: extracted, published, wired and verified. Every moved attribute produces the same `drvPath`
it produced before the move, so nothing rebuilt.

Repository: <https://github.com/neg-serg/nixos-pkgs> (public, branch `main`, head `c1df688`). Live
checkout: `/home/neg/src/nix/nixos-pkgs`.

## What moved out of this tree

35 "fetch recipe" packages under `packages/<name>/` — `dnsglobe`, `flow`, `geekbench-ai`, `lsfg-vk`,
`neru`, `niri-screen-time`, `nixard`, `oryx`, `terrascope`, `topowall`, `tuigram`, `uutils-sort`,
`atrium`, `audio-cpp`, `camillaeq`, `camillagui`, `craft-anything`, `figcraft`, `hdspeconf`,
`hypr-kdeconnect-fix`, `hyprqt6engine`, `irori`, `linux-firmware-minimal`, `llama-cpp-inkling`,
`matugen-themes`, `open-audio-analyzer`, `pw-audioshare`, `pycamilladsp`, `pycamilladsp-plot`,
`rustgis`, `sola-mpd`, `solidcraft`, `swayimg`, `tewi`, `tmd-top`.

Their overlay entries moved with them. `pkgs.neg.*` names stay under `neg`, everything else becomes
a top-level attribute.

## What had to be fixed in nixos-pkgs first

1. **`overlay.nix` returned only `neg`** (plus `python3-lto` and `buildFHSEnv`), so the top-level
   packages its domain overlays define were computed and dropped. It now merges
   `overlays/migrated.nix`, which carries the moved entries and returns their top-level names.
1. **`lib.mkMeta` was missing.** The moved package files use the host's shared `meta` builder;
   `lib/mkMeta.nix` moved with them and the overlay extends `prev.lib` with it, so the package files
   evaluate unchanged.
1. **`neg.functions.mkCraftApp` was missing.** `lib/mkCraftApp.nix` moved too and is exposed in
   `overlays/functions.nix`; `figcraft`, `craft-anything` and `solidcraft` call it.
1. **The Rust slimming wrapper.** Six moved packages are Rust and the host wraps them with
   `inputs.rust-pkgs.lib.slim` (LTO, one codegen unit, stripped binaries). `nixos-pkgs` now takes
   `rust-pkgs` as an input and applies the wrapper to the same names; the host makes it follow its
   own `rust-pkgs`.
1. **nixpkgs was pinned to the floating `nixos-26.05`** and had no lockfile. It is pinned to the
   revision the host runs and locked, so a standalone build here and the host build resolve to the
   same derivations.

## How the host consumes it

- `flake.nix`: `inputs.neg-pkgs.inputs.rust-pkgs.follows = "rust-pkgs"` — one Rust package set, not
  two.
- `flake.lock`: `neg-pkgs` locked at `c1df688`, `neg-pkgs/rust-pkgs` following.
- `packages/overlays/*.nix`: the 35 entries are gone; the attributes now come from the input's
  overlay, which is applied after the local one.

## Verification done that day

- **`drvPath` equality for all 35 attributes**, recorded before the change and compared twice: once
  with the new input active while the local entries were still present (the input's overlay wins, so
  the recipes had to agree), and once after deleting them. Both runs: 0 mismatches. The two
  intermediate failures that this caught were the Rust slimming (six packages) and `mkCraftApp` (the
  three craft apps).
- Here: `just fmt`, `just lint` (README statistics 509 → 474 Nix files), `just check`, the toplevel
  build and the switch — the toplevel is the same store path as the running generation, because
  every derivation is unchanged.

## What stays in this tree and why

- `aura`, `hyprwhspr`, `wallhaven`, `wl-switcher` — Vicinae extensions built from
  `files/gui/vicinae-extensions/` (the files are host configuration).
- `waylandar`, `wl` — their sources are host flake inputs (`inputs.waylandar`, `inputs.wl`).
- `renoise-redux` — needs the licensed Renoise installers through the `renoise-src` path input.
- `dsh` — the harness packaging, built with `dsh-patch` from `rust-pkgs`.
- `elio`, `lazytail` — Rust crates from `rust-pkgs`, wrapped with `rustSlim`.
- `sonda`, `vsncnn`, `joern`, `herdr`, `snd-hdspe`, `vivaldi` — portable in principle, left for a
  second batch: each carries an extra argument or a renamed attribute (`vivaldi-fixed`,
  `snd-hdspe`'s kernel, `herdr`'s `overrideAttrs`) that the migration has to reproduce, and their
  verification is the same `drvPath` comparison.
- `oaa-cli` and `ttf-code` look unwired by directory name but are live: their overlay entries are
  `oaa = call (pkg "oaa-cli")` and the four `ttf-code200x` variants that
  `callPackage ./ttf-code { variant = ...; }`.

## Gaps to fix later

1. **The second batch** (six packages above) with the same verification.
1. **`nixos-pkgs` has no CI.** Its flake evaluates, but nothing gates a push; the patch to add is
   the same `nix flake check` shape the other extracted repositories use.
1. **The domain overlays still carry stale copies** of some moved entries and of the host's
   `dev.nix` overrides (`bpftrace`, `gnuradio`, `mbedtls_2`). They are shadowed by the host's own
   overlays but they are dead weight in that repository.
