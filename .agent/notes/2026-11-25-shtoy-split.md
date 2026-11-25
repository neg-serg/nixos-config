# 2026-11-25 — shtoy moved to its own flake

Status: extracted, published and wired. The gaps at the bottom are deliberate and each names how to
close it.

Repository: <https://github.com/neg-serg/shtoy> (public, branch `main`, initial import `334e0b5`).
Live checkout: `/home/neg/src/shtoy`.

## What moved out of this tree

| was here                                     | now                                                                                                   |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `packages/shtoy/{Cargo.toml,Cargo.lock,src}` | repository root                                                                                       |
| `packages/shtoy/default.nix`                 | `package.nix` there (plain `meta`, GitHub homepage, `platforms = lib.platforms.linux`, `withViewer`)  |
| —                                            | `flake.nix`, `flake.lock`, `LICENSE`, `.gitignore`, `.github/workflows/ci.yml`, `README.md`, `tests/` |

The host glue stays here: `modules/user/nix-maid/cli/local-bin.nix` keeps `pkgs.neg.shtoy` for
`~/.local/bin/shtoy`, and the shader collection under `files/gui/shtoy` (the two shipped ports plus
their textures) stays too — it is user data shipped to `$XDG_CONFIG_HOME/shtoy`, not part of the
crate.

One packaging detail changed with the move: `package.nix` gained `withViewer ? true`, so
`nix flake check` can run the CLI against a stub `esshader` without pulling the viewer closure. The
argument is not called `wrap` — `callPackage` fills every argument whose name exists in the package
set (nixpkgs has a Go tool named `wrap`), so the default would silently never apply.

## How the host consumes it

- `flake.nix`: `shtoy.url = "github:neg-serg/shtoy"`, `inputs.nixpkgs.follows = "nixpkgs"`.
- `packages/overlays/tools.nix`: `shtoy = inputs.shtoy.packages.<system>.default`; the attribute
  name did not change, so the local-bin symlink and the `--list` shader paths work as before.
- The name left `rustNegNames` together with its `neg` chunk entry in `packages/overlay.nix`: the
  chunk lookup `chunks.${name}` throws on a missing attribute, so the two move as one. An extracted
  package is no longer `rustSlim`-wrapped here, the same tradeoff as `mpd-voice` and
  `sing-box-proxy`.
- README statistic: Nix Files 587 → 586.

## Verification done that day

In the new repository: `nix flake lock`, `nix flake check -L` green — the `cli` check runs the
binary against a stub `esshader` and asserts the `--list` layout (cached first, shipped ids the
cache does not shadow, hidden and non-`.frag` names skipped), the rewrite (dropped `#version`/`#!`,
the `iFrame` define), the automatic GLES2 switch for `texture2D`, the unbound-channel note, stdin
handling and both `--save` rejections. `nix build .#default` produced the wrapped binary;
`cargo fmt --check` clean through the devShell (the host's rustup toolchain is broken against the
current glibc).

Here: `nix build .#nixosConfigurations.trantor.pkgs.neg.shtoy` through the new input, the wrapper's
`PATH` carries `esshader`, `just fmt`, `just lint`, `just check`.

## Gaps to fix later

1. **No `#[test]` items.** The flake check is an end-to-end CLI pass, not unit coverage of the
   parsers (`prepare`, `source`, `cli`), and `src/test_support.rs` is an unreferenced file that
   moved as-is.
1. **CI has no Nix cache.** `nix build .#default` compiles the reqwest/rustls closure on every push.
1. **The default `nixpkgs` pin copies this host's rev.** A consumer that does not pass
   `inputs.nixpkgs.follows` gets that snapshot; the host does pass it.

## Commits

- `334e0b5` — initial import (crate + packaging + docs + CI + CLI check).
- This tree: the extraction commit (input, overlay entry, package removal, README statistic).
