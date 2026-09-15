# Overlay Pattern and Helpers

## Overview

- Entry: `packages/overlay.nix`
  - Loads overlays from
    `packages/overlays/{functions,tools,media,dev,gui,aur-ported,fix-tinycc,vendored-sources,disable-checks}.nix`
  - Merges their attrsets and exposes a combined namespace under `pkgs.neg`
  - `disable-checks.nix` is merged last on purpose (its `overrideAttrs` resets prior overrides on
    the same package)
  - `flake/lib.nix` applies the external `neg-pkgs` overlay *after* this one, so anything both
    overlays define (e.g. `python3-lto`, `buildFHSEnv`, several `pkgs.neg.*` entries) resolves to
    the neg-pkgs version
- Structure is intentional and should be kept as:
  - functions.nix — shared helpers under pkgs.neg.functions
  - tools.nix — CLI/desktop helpers under pkgs.neg.\*
  - media.nix — audio/video tools under pkgs.neg.\*
  - dev.nix — development/toolchain tweaks and scoped overrides
  - vendored-sources.nix — overrides for region-blocked/unreachable upstream fetches, using vendored
    tarballs/patches from `files/sources` and `files/patches` (the vendored-tarball note lives
    there)

## Helpers (`pkgs.neg.functions`)

- callPkg path extraArgs
  - `prev.callPackage path extraArgs`, injecting `inputs` automatically when the package declares an
    `inputs` argument (sniffed with `builtins.functionArgs`).
  - Alias it once per overlay (`callPkg = final.neg.functions.callPkg;`) instead of redefining it.
  - It is the only shared helper: the previous `overridePyScope`, `overrideScopeFor`,
    `withOverrideAttrs`, `overrideRustCrates`, `overrideGoModule`, `withAutoreconf` and
    `withCMakePolicyFloor` had no callers anywhere in the repo and were removed (audit 2026-09-15) —
    use `prev.<set>.overrideScope` / `drv.overrideAttrs` directly.

## Usage examples

1. Add a package that needs the flake inputs:

   ```nix
   # packages/overlays/tools.nix
   inputs: final: prev:
   let
     callPkg = final.neg.functions.callPkg;
   in
   {
     neg = {
       mystat = callPkg (packagesRoot + "/mystat") { }; # CLI that reads inputs.<name>
     };
   }
   ```

1. Override a scoped package set (no helper needed):

   ```nix
   _final: prev: {
     python3Packages = prev.python3Packages.overrideScope (self: super: {
       ncclient = super.ncclient.overrideAttrs (_: { src = prev.fetchFromGitHub { /* ... */ }; });
     });
   }
   ```

## Conventions

- Keep domain-specific packages in tools.nix / media.nix / dev.nix.
- Put only reusable helpers into functions.nix.
- When overriding scoped sets (e.g., python3Packages), use `overrideScope` and merge the result with
  `//`.
- Expose custom packages under pkgs.neg to avoid name clashes with upstream.

## Validation tips

- nix flake check -L (project root) to ensure overlays evaluate.
- nix repl or nix eval can be used to inspect pkgs.neg.\* derivations.
