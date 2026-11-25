# 2026-11-25 — 41 packages moved to nixos-pkgs

Status: extracted, published, wired and verified. Every moved attribute produces the same `drvPath`
it produced before the move, so nothing rebuilt.

Repository: <https://github.com/neg-serg/nixos-pkgs> (public, branch `main`, head `bd7f708`). Live
checkout: `/home/neg/src/nix/nixos-pkgs`.

## What moved out of this tree

41 packages in two batches.

The first batch is the self-contained "fetch recipe" packages: `dnsglobe`, `flow`, `geekbench-ai`,
`lsfg-vk`, `neru`, `niri-screen-time`, `nixard`, `oryx`, `terrascope`, `topowall`, `tuigram`,
`uutils-sort`, `atrium`, `audio-cpp`, `camillaeq`, `camillagui`, `craft-anything`, `figcraft`,
`hdspeconf`, `hypr-kdeconnect-fix`, `hyprqt6engine`, `irori`, `linux-firmware-minimal`,
`llama-cpp-inkling`, `matugen-themes`, `open-audio-analyzer`, `pw-audioshare`, `pycamilladsp`,
`pycamilladsp-plot`, `rustgis`, `sola-mpd`, `solidcraft`, `swayimg`, `tewi`, `tmd-top`.

The second batch is the ones that needed an entry reproduced exactly: `joern` (under `neg`),
`sonda`, `vsncnn`, `snd-hdspe` (with the kernel argument), `vivaldi` (exposed as `vivaldi-fixed`)
and `herdr` — the last one is patches only, so its overlay entry moved while the directory has no
`default.nix` and the input's overlay builds the patched nixpkgs package.

## What had to be fixed in nixos-pkgs first

1. **`overlay.nix` returned only `neg`** (plus `python3-lto` and `buildFHSEnv`), so the top-level
   packages its domain overlays define were computed and dropped. It now merges
   `overlays/migrated.nix`, which carries the moved entries and returns their top-level names.
1. **`lib.mkMeta` was missing.** The moved package files use the host's shared `meta` builder;
   `lib/mkMeta.nix` moved with them and the overlay extends `prev.lib` with it.
1. **`neg.functions.mkCraftApp` was missing.** `lib/mkCraftApp.nix` moved too and is exposed in
   `overlays/functions.nix`; `figcraft`, `craft-anything` and `solidcraft` call it.
1. **The Rust slimming wrapper.** Seven moved packages are Rust and the host wraps them with
   `inputs.rust-pkgs.lib.slim`. `nixos-pkgs` now takes `rust-pkgs` as an input, applies the wrapper
   to the same names in the overlay and in `packages.nix`, and the host makes it follow its own
   `rust-pkgs`.
1. **`packages.nix` called every directory with no arguments**, so eight entries aborted: `exo`,
   `skwd`, `sqlit`, `talktype` and `wl` need flake inputs, `snd-hdspe` a kernel, `game-scripts` was
   a NixOS module fragment and `surfingkeys-conf` needed the host's `files/surfingkeys.js`. The list
   now passes what the overlay passes; the two dead directories and the dangling overlay entry are
   gone, and directories without a `default.nix` are skipped.
1. **nixpkgs was pinned to the floating `nixos-26.05`** and had no lockfile. It is pinned to the
   revision the host runs and locked.

## Cleaned up in nixos-pkgs

`overlay.nix` returns only `neg` plus `python3-lto` and `buildFHSEnv`, so every top-level entry in
the domain overlays was computed and dropped. The stale copies of moved entries (`matugen-themes`,
`swayimg`, `hdspeconf`) and the whole `overlays/dev.nix` (its four entries were top-level only:
`bpftrace`, `mbedtls_2`, `gnuradio`, `pre-commit`) are gone, together with the merge line that fed
them. The host's derivations are unchanged by that cleanup.

CI: one workflow evaluates every `packages.nix` entry and runs `nix flake check`; the stale
`build.yml` (a channel the flake does not use, and a build of every package) is gone. It is green on
`main`.

## How the host consumes it

- `flake.nix`: `inputs.neg-pkgs.inputs.rust-pkgs.follows = "rust-pkgs"` — one Rust package set, not
  two.
- `flake.lock`: `neg-pkgs` locked at `bd7f708`, `neg-pkgs/rust-pkgs` following.
- `packages/overlays/*.nix`: the entries are gone; the attributes come from the input's overlay,
  which is applied after the local one.

## Verification

- **`drvPath` equality for all 41 attributes**, recorded before each batch and compared with the
  input active: 0 mismatches. What the comparison caught and forced into the design: the Rust
  slimming (`sonda` in the second batch) and `mkCraftApp` (the three craft apps); `herdr` and
  `snd-hdspe` kept the argument or override their host entry had, so their derivations did not move
  either.
- Here: `just fmt`, `just lint`, `just check`, the toplevel build — the system path stays the one
  the running generation has, because every derivation is unchanged.

## What stays in this tree and why

- `aura`, `hyprwhspr`, `wallhaven`, `wl-switcher` — Vicinae extensions built from
  `files/gui/vicinae-extensions/` (the files are host configuration).
- `waylandar`, `wl` — their sources are host flake inputs.
- `renoise-redux` — needs the licensed Renoise installers through the `renoise-src` path input.
- `dsh` — the harness packaging, built with `dsh-patch` from `rust-pkgs`.
- `elio`, `lazytail` — Rust crates from `rust-pkgs`, wrapped with `rustSlim`.
- `oaa-cli` and `ttf-code` look unwired by directory name but are live: their overlay entries are
  `oaa = call (pkg "oaa-cli")` and the four `ttf-code200x` variants that
  `callPackage ./ttf-code { variant = ...; }`.

## Gaps to fix later

1. **`fix-tinycc.nix`, `disable-checks.nix`, `fonts.nix` and `aur-ported.nix`** are in the same
   position `dev.nix` was: top-level entries the overlay drops. `disable-checks.nix` and `fonts.nix`
   are imported for their `.neg` only. A pass should decide per file whether it has any consumer.
1. **The remaining package directories** in `/etc/nixos/packages` are host-bound (the list above);
   moving them would mean carrying host configuration or another flake input, not a packaging
   recipe.

## Commits

- `nixos-pkgs`: import of the first batch, `lib.mkMeta`, `neg.functions.mkCraftApp`, the `rust-pkgs`
  input and wrapper, CI + README, the `packages.nix` fix, the second batch, the flake-output
  slimming, and the dead-entry cleanup.
- This tree: the first batch, the input pin to the fixed list, and the second batch (with the unused
  `paths` argument the move made dead).

## Follow-up (same day, later)

- **`ttf-code` moved too.** The four Code200x variants are `packages/ttf-code/` in `nixos-pkgs` now,
  wired as the top-level `ttf-code2000 … ttf-code20x3` in `packages.nix` and
  `overlays/migrated.nix`; the host's overlay entries and `packages/ttf-code/` are gone, and the
  toplevel `drvPath` stayed `374pd45z…` because the recipe and its sources did not change.
- **The host's `lib/mkCraftApp.nix` is deleted, and the builder is re-exported from the input.** The
  three craft apps in `nixos-pkgs` call `neg.functions.mkCraftApp`, and the overlay whose
  `functions` the host package set ends up with is this tree's — so removing the copy without a
  re-export broke `pkgs.figcraft` (caught by `just check`, after the toplevel eval had passed
  because the apps are on-demand). `packages/overlays/functions.nix` now builds the builder from
  `inputs.neg-pkgs + "/lib/mkCraftApp.nix"`, byte-identical to the deleted file.
