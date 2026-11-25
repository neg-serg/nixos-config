# 2026-11-25 — the music-AI payloads moved to their own repository

Status: extracted, published (`github:neg-serg/music-ai-libs`, `a97ffc6`), wired and built.

Repository: <https://github.com/neg-serg/music-ai-libs> (public). Live checkout:
`~/src/nix/music-ai-libs`.

## What moved out of this tree

| was here                                   | now                                                                                     |
| ------------------------------------------ | --------------------------------------------------------------------------------------- |
| `packages/local-bin/lib/music_embed.py`    | `lib/music_embed.py`                                                                    |
| `packages/local-bin/lib/music_tags.py`     | `lib/music_tags.py`                                                                     |
| `packages/local-bin/lib/music_mtg.py`      | `lib/music_mtg.py`                                                                      |
| `packages/local-bin/lib/music_describe.py` | `lib/music_describe.py`                                                                 |
| `packages/local-bin/lib/moss_music.py`     | `lib/moss_music.py`                                                                     |
| —                                          | `package.nix` (payloads + `compileall`), `flake.nix`, `test_music_libs.py`, `README.md` |

## Why this boundary and not a bigger one

The launchers (`music-embed`, `music-tags`, `audio-analysis`, `music-mtg-tags`, `moss-music`) are
*rendered* from NixOS options in `modules/user/nix-maid/cli/local-bin.nix`: ten substitutions carry
the venv site-packages, the model directories, the HF cache and the interpreter. That rendering
layer cannot leave the host without inventing an option interface for another machine, so the split
is: payloads here, launchers and their substitutions there. The wrappers already ran
`"$PY" "$LIB/<module>.py"`, so the only thing that changed is where `$LIB` points.

## Decisions taken with the move

- **The suite is real.** The payloads import torch/transformers inside the functions that use them,
  so a stdlib-only suite can import every module and cover the answer parsing, the settings keys and
  the resume cache without a venv, a model or a GPU. 18 tests, run by `nix flake check`.
- **The package is a payload copy plus a syntax gate.** `compileall` proves every module parses;
  bytecode goes to the build directory, not into `$out`.
- **Two shell consumers build the package instead of naming a checkout path:** `just music-selftest`
  and `scripts/dev/music-ai-rocm.sh`, the same pattern `music-index-tools` already used there.

## How the host consumes it

- `flake.nix`: `music-ai-libs` (`github:neg-serg/music-ai-libs`, `inputs.nixpkgs.follows`).
- `packages/overlays/tools.nix`: `callPkg (inputs.music-ai-libs + "/package.nix") { }` →
  `pkgs.neg.music-ai-libs`; `packages/flake/custom-packages.nix` exposes it as `.#music-ai-libs`.
- `modules/user/nix-maid/cli/local-bin.nix`: `"@MUSIC_AI_LIB@" = "${pkgs.neg.music-ai-libs}/lib"`.
- `packages/local-bin/lib/` is gone; `packages/local-bin/bin/*` and `_music_ai_env.sh` are
  unchanged.

## Verification done that day

- In the repository: `python3 -m unittest discover` (18 tests), `nix flake check` (build + suite),
  `nix build .#default`.
- Here: `just fmt`, `just lint` (17 gates, including `just music-selftest` building the new
  package), the toplevel eval and build, and the switch.

## Gaps to fix later

1. **The launchers are still untested.** The payload functions that touch audio (decoding windows,
   the MTG head scoring, the checkpoint resume in `run_batch`) need the venv and a model; the suite
   covers their pure inputs.
1. **`music-ai-rocm.sh` and `just music-selftest` now depend on a Nix build** to find the payloads.
   Both already did that for `music-index-tools`, and the package is in the system closure, so the
   build is a store hit in practice.
