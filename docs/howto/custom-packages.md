# Custom packages and vendored sources

- All local derivations (`pkgs.neg.*`, CLI wrappers, MCP servers, etc.) now live under the top-level
  `packages/` directory.
- The overlay is applied in `flake/lib.nix` (`mkPkgs`); flake outputs for the custom packages are
  exposed via `packages/flake/custom-packages.nix` (e.g. `nix build .#omp`).
- Vendored sources live in `files/sources/` and are referenced as relative path literals (see the
  header of `packages/overlays/vendored-sources.nix`). Files above GitHub's 100 MB limit cannot be
  committed, so the licensed Renoise/Redux installers sit outside the repository in
  `/home/neg/nixos-src/renoise` and arrive as the `renoise-src` path input (`flake.nix`,
  `flake = false`), consumed as `inputs.renoise-src + "/<tarball>"`. Two consequences: a clone
  without that directory fails to evaluate `renoise`/`renoise-redux`, and relocating such a file
  inside the tree does not help — the flake source contains tracked files only, and absolute paths
  are rejected in pure evaluation.
