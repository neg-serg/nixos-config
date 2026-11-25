# AGENTS usage for packages/

Scope

- Applies to packaging under `packages/` (overlays, local packages, `local-bin/`).
- Repo-wide conventions still apply.

Guidelines

- Add new packages in their own subdirectories and wire them through `packages/overlays/*.nix`,
  aggregated by `packages/overlay.nix` (domains: functions/tools/media/dev/gui).
- Prefer overlays + `callPackage` over ad-hoc nixpkgs edits; pass `inputs` following existing
  overlay patterns when required.
- Fill out `meta` fields (description, homepage, license, platforms, maintainers) and keep fetcher
  hashes current; note when using binary sources.
  - `maintainers = [ ]` is the convention for local-only packages (nothing here is upstream), and
    environments built with `python3.withPackages` carry no `meta` at all — say so in a comment
    instead of inventing one.
- Put small helper scripts intended for `$PATH` in `packages/local-bin` with clear names and minimal
  dependencies.
- Rust crates are no longer packaged here: they live in `github:neg-serg/rust-pkgs` (live checkout
  `~/src/nix/rust-pkgs`), which owns their manifests, lockfiles and `package.nix` files. This tree
  calls `final.callPackage (inputs.rust-pkgs + "/<crate>/package.nix") { }` against its own package
  set and keeps the `pkgs.neg.<crate>` names (see `packages/overlay.nix`); do not copy a crate back
  in.
- The Nix builds are no longer packaged here either: `nix-eval-patched` (upstream Nix plus the
  evaluation-speedup patch stack) and `nix-det-pgo` (Determinate Nix rebuilt with PGO) live in
  `github:neg-serg/nix-optimized` (live checkout `~/src/nix/nix-optimized`).
  `packages/overlays/dev.nix` calls
  `prev.callPackage (inputs.nix-optimized + "/<package>/package.nix")` and keeps the `pkgs.neg.*`
  attribute names. Do not add a Nix patch stack back into this tree.
- The SuperCollider live-coding stack is no longer packaged here either: UGen plugins, sclang
  quarks, Dirt-Samples, VST hosting and their shared `mkScQuark`/`mkScPlugin` builders live in
  `github:neg-serg/nixos-music` (live checkout `~/src/nix/nixos-music`) and arrive as the
  `nixos-music` flake input, reachable as `pkgs.music.<name>`. Do not add an SC package back into
  this tree.
- For a project that still carries a manifest in this tree, do not repeat its version in
  `default.nix`; read the manifest instead:
  `version = (lib.importTOML ./Cargo.toml).package.version;`. The `manifest-version` lint guard
  rejects a literal next to a `Cargo.toml`.
