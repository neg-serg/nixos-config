# AGENTS usage for packages/

Scope
- Applies to packaging under `packages/` (overlays, local packages, `local-bin/`).
- Repo-wide conventions still apply.

Guidelines
- Add new packages in their own subdirectories and wire them through `packages/overlays/*.nix`, aggregated by `packages/overlay.nix` (domains: functions/tools/media/dev/gui).
- Prefer overlays + `callPackage` over ad-hoc nixpkgs edits; pass `inputs` following existing overlay patterns when required.
- Fill out `meta` fields (description, homepage, license, platforms, maintainers) and keep fetcher hashes current; note when using binary sources.
- Put small helper scripts intended for `$PATH` in `packages/local-bin` with clear names and minimal dependencies.
