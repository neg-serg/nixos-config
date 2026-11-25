# 2026-11-25 — mpd-voice moved to its own flake

Status: extracted, published and wired. The gaps at the bottom are deliberate and each names how to
close it.

Repository: <https://github.com/neg-serg/mpd-voice> (public, branch `main`, initial import
`2835c88`). Live checkout: `/home/neg/src/mpd-voice`.

## What moved out of this tree

| was here                                         | now                                                                                         |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `packages/mpd-voice/{Cargo.toml,Cargo.lock,src}` | repository root                                                                             |
| `packages/mpd-voice/default.nix`                 | `package.nix` there (standard `meta`, homepage on GitHub, `platforms = lib.platforms.unix`) |
| `packages/mpd-voice/README.md`                   | rewritten for the standalone project                                                        |
| —                                                | `flake.nix`, `flake.lock`, `LICENSE`, `.gitignore`, `.github/workflows/ci.yml`              |

The host glue stays here: `modules/media/audio/mpd-voice.nix` (system package plus the
`/etc/xdg/mpd-voice/config.toml` it writes), the `features.media.audio.mpdVoice.*` options, and the
Hyprland binding that runs `mpd-voice once`.

Documentation that described the old two-tree port was corrected rather than carried over: the
`src/main.rs` header no longer says "stage 1, the Python tree keeps building", the `Cargo.toml`
comment no longer points at `packages/Cargo.toml`, and the README dropped the Python parity-harness
file references and the stale `nix build .#mpd-voice-rs` line.

## How the host consumes it

- `flake.nix`: `mpd-voice.url = "github:neg-serg/mpd-voice"`, `inputs.nixpkgs.follows = "nixpkgs"`.
- `packages/overlays/tools.nix`: `pkgs.neg.mpd-voice` is the input's `packages.<system>.default`.
  The module and `packages/flake/custom-packages.nix` now spell `pkgs.neg.mpd-voice`; the flake
  alias `nix build .#mpd-voice` is unchanged.
- `packages/overlays/media.nix` no longer `callPackage`s the local directory, and the name left
  `rustTopNames` — an extracted package cannot be `rustSlim`-wrapped here any more, the same as
  `music-index-tools`, `tgchat-rs` and the other external crates.
- README statistic: Nix Files 590 → 589.

## Verification done that day

- In the new repository: `nix flake lock`, `nix build` → `bin/mpd-voice`, `rustfmt --check` clean
  over `src/*.rs`, `nix flake check -L` green (the `cli` check runs `phrases`, `parse` and
  `say --dry-run` in the sandbox — no microphone, MPD or STT needed).
- Here: `nix build .#mpd-voice` produced a working binary through the new input, `just fmt`,
  `just lint` (18/18 after the README statistic update), then the toplevel build.

## Gaps to fix later

1. **No test suite.** The crate has no `#[test]` items; the old packaging comment's "104 tests" was
   stale and is not repeated. The flake check covers only the audio-free CLI paths; the parser, the
   MPD client and the VAD have no fixtures. Restoring the Python parity harness is not possible —
   that tree is gone — so real coverage means new Rust tests.
1. **CI has no Nix cache.** `cachix/install-nix-action` builds the package from scratch on every
   push; fine for one small crate, worth a cache if the closure grows.
1. **The default `nixpkgs` pin copies this host's rev** (`2786a2a`). A consumer that does not pass
   `inputs.nixpkgs.follows` gets that snapshot; the host does pass it.
1. **The defaults are host-specific** (`music-similar`, `music-describe`, `~/.cache/music-mtg/`,
   `:8001`/`:8002`). They are overridable through the config file and `MPD_VOICE_*`, but the client
   is not a general-purpose MPD front end.

## Commits

- `2835c88` — initial import (crate + packaging + docs + CI).
- This tree: the extraction commit (input, overlay entry, package removal, README statistic).
