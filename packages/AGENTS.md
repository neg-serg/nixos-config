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
- Do not repeat a Rust project's version in `default.nix`; read the manifest instead:
  `version = (lib.importTOML ./Cargo.toml).package.version;`. The store path, the package attr and
  the binary (`CARGO_PKG_VERSION`) then share one source, and a bump is the manifest plus its
  lockfile(s) — `just bump <package> [<version>]` does both. The `manifest-version` lint guard
  rejects a literal next to a `Cargo.toml`.
