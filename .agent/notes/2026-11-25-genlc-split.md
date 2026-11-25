# 2026-11-25 — genlc moved to its own project

Status: extracted, published, wired and verified. The gaps at the bottom are deliberate and each
names how to close it.

Repository: <https://github.com/neg-serg/genlc> (public, branch `master`, commit `007be09`). Live
checkout: `/home/neg/src/genlc`.

The repository already existed and was **archived**: it held the Python genlc (Mark Bergsma's GPLv3
module). It was unarchived (`gh api -X PATCH repos/neg-serg/genlc -f archived=false`), the
description replaced, and the Rust tree committed on top of the Python history — the Python code is
reachable from git, not from `master`.

## What moved out of this tree

| was here                                                          | now                                                                                               |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `packages/genlc-rs/src/{main,lib,client,daemon,plan,protocol}.rs` | repository root `src/`                                                                            |
| `packages/genlc-rs/Cargo.{toml,lock}`                             | repository root (`[workspace]` of its own; the lock was pruned to this crate)                     |
| `packages/genlc-rs/default.nix`                                   | `package.nix` there (plain `meta`, GitHub homepage, `platforms = lib.platforms.linux`)            |
| —                                                                 | `flake.nix`, `flake.lock`, `LICENSE` (MIT), `.gitignore`, `.github/workflows/ci.yml`, `README.md` |

The host glue stays here: the adapter udev rule (`files/hardware/udev/trantor-host.rules`), the
`genlc daemon` user unit (`modules/user/nix-maid/sys/user-services/glm-monitoring.nix`), the media
keybindings in `files/gui/hypr/hyprland.lua` and the system package list.

## How the host consumes it

- `flake.nix`: `genlc.url = "github:neg-serg/genlc"`, `inputs.nixpkgs.follows = "nixpkgs"`.
- `packages/overlays/tools.nix`: `pkgs.neg.genlc` is the input's `packages.<system>.default`, next
  to the other extracted packages (`mpd-voice`, `tint`, `tgchat-rs`, …). Unlike before the
  extraction the package is top-level no longer: three consumers moved with it —
  `modules/media/audio/core-packages.nix`, `packages/flake/custom-packages.nix` and the unit's
  `ExecStart`.
- The name left `rustTopNames` in `packages/overlay.nix` together with the local `neg` chunk entry;
  an extracted package is no longer `rustSlim`-wrapped here, the same tradeoff as `mpd-voice` and
  `hypr-win-list`.
- `packages/genlc-rs` is gone, and with it the `genlc-rs` member of `packages/Cargo.toml` and its
  package block in `packages/Cargo.lock` (nothing depends on the crate).
- README statistic: Nix Files 588 → 587.
- `just bump genlc` no longer applies: a version bump is the manifest plus `Cargo.lock` in the
  project checkout.

## Packaging decisions taken with the move

- **`libusb` left the derivation.** `cargo` builds hidapi's own hidraw C implementation against
  `libudev`; `ldd` on the result lists `libudev` and no `libusb`, and the old `postFixup` rpath only
  added an unused runtime dependency. `pkg-config`, `udev` and `hidapi` stay as inputs.
- **The version still comes from the manifest**, so clap's `CARGO_PKG_VERSION` and the store path
  cannot drift.
- **The flake check pins the CLI surface**: `--version` equals the manifest version and every
  subcommand is still listed. It opens no adapter, so `nix flake check` runs on a machine without a
  GLM bus.
- CI runs `cargo fmt --check`, `cargo clippy --all-targets`, `cargo build --release`, `nix build`
  and `nix flake check`; the clippy step does not deny warnings (see the gaps).

## Verification done that day

In the new repository: `nix build .#default` produced `genlc-0.2.0` (`--version` prints
`genlc 0.2.0`), `nix flake check -L` green via the `cli` check, `cargo fmt --check` clean,
`cargo clippy` warns on 8 lints. `git push` went to `master` after the unarchive.

Here: `nix build .#nixosConfigurations.trantor.pkgs.neg.genlc` builds through the new input
(`/nix/store/kiqygi649lglf1q00dnlk65p06rag7gr-genlc-0.2.0`), `just fmt`, `just lint`, then the
toplevel build and the agent switch.

## Gaps to fix later

1. **License provenance.** The repository's Python tree was GPLv3 and the Rust crate kept `MIT` in
   its in-tree `meta`. `protocol.rs` says its transport "matches Python genlc USB transport"
   (`USBTransport.send()`), so if that code is a translation of the GPLv3 source rather than a
   reimplementation from the public qlm notes, `MIT` is wrong and the LICENSE plus `meta.license`
   have to go back to `gpl3Plus`. Decide and make the two agree; the split note cannot settle it.
1. **Eight clippy warnings** (`collapsible_if` in `daemon.rs`/`protocol.rs`/`main.rs`, a redundant
   `println!` reference, `manual_is_multiple_of`). CI runs clippy without `-D warnings` because the
   extraction was not a lint pass; fixing them is a small follow-up in the project, after which the
   CI flag can be added.
1. **No `#[test]` items.** The flake check exercises the CLI surface only; the protocol builders,
   the CRC and the plan parser have no unit tests (the Python tree had them).
1. **CI has no Nix cache.** `nix build .#default` pulls the Rust toolchain and hidapi closure from
   `cache.nixos.org` on every push.
1. **The default `nixpkgs` pin copies this host's rev.** A consumer that does not pass
   `inputs.nixpkgs.follows` gets that snapshot; the host does pass it.

## Pre-existing issues seen while wiring (not touched)

1. `packages/overlay.nix`'s `rustTopNames` still lists `tint`, but no top-level `tint` exists in the
   chunk overlays — the extracted `tint` lives at `pkgs.neg.tint`.
   `nix eval .#nixosConfigurations.trantor.pkgs.tint.name` therefore fails with
   `attribute 'tint' missing`; nothing reads it, which is why it never surfaced.
1. `packages/Cargo.toml` still lists `tint` as a workspace member after that directory was
   extracted, so the workspace file cannot be used as is.

## Commits

- `007be09` — the Rust tree replaces the Python one (crate, packaging, docs, CI, CLI check).
- This tree: the extraction commit (input, overlay entry, consumer paths, package removal, README
  statistic).
