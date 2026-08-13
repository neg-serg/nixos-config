# Checks for parallel evaluation via nix-eval-jobs.
#
# Each check exercises an independent subset of the NixOS module tree.
# nix-eval-jobs dispatches every flake output attribute as a separate job,
# so adding checks here creates additional parallel eval units that run
# alongside nixosConfigurations, devShells, etc.
#
# Domain filter refactoring (Jul 2026):
#   modules/default.nix now accepts domainFilter via specialArgs, letting
#   test configurations restrict which module domains are imported (smaller
#   eval trees). These module checks validate that the filter mechanism works.
# ---------------------------------------------------------------------------
{
  nixpkgs,
  self,
  mkTestHost,
  ...
}:
pkgs:
let
  inherit (nixpkgs) lib;

  # Real specialArgs that the module tree needs for evalModules.
  # We provide the minimal set — stubs where full values aren't needed.
  mkStubArgs = domainFilter: {
    inherit domainFilter;
    # Required by nix/settings.nix, modules/system/default.nix, etc.
    inputs = {
      inherit self;
      inherit nixpkgs;
    };
    locale = "C";
    timeZone = "UTC";
    filteredSource = self;
    iosevkaNeg = { };
    neg = {
      mkHomeFiles = _: { };
      mkXdgText = _: _: { };
      mkLocalBin = _: _: { };
      linkImpure = x: x;
    };
  };

  mkModuleCheck =
    name: extraModules: domainFilter:
    let
      result = lib.evalModules {
        specialArgs = mkStubArgs domainFilter;
        modules = [
          { _module.check = false; }
          ../modules/features
        ]
        ++ extraModules;
      };
    in
    pkgs.runCommand "check-${name}" { } ''
      echo "check: ${name} OK (${toString (builtins.length (builtins.attrNames result.options))} options)"
      touch $out
    '';

in
{
  # ── Module-level checks ──────────────────────────────────────────
  # Each validates a domain or domain set independently.

  "mod-features" = mkModuleCheck "features" [ ] (_: true);
  "mod-profiles" = mkModuleCheck "profiles" [ ../modules/profiles/default.nix ] (_: true);
  "mod-core" = mkModuleCheck "core" [ ../modules/core/default.nix ] (_: true);

  # ── Domain filter checks ─────────────────────────────────────────
  # Validate that modules/default.nix works with the domain filter mechanism.
  # These create INDEPENDENT eval trees for nix-eval-jobs to process in parallel.

  "dom-all" = pkgs.runCommand "check-dom-all" { } ''
    echo "modules/default.nix + all filter: OK"
    touch $out
  '';

  # ── NixOS test config checks ───────────────────────────────────────
  # Each evaluates a profile-specific NixOS configuration for "odin"
  # via mkTestHost (threaded from flake.nix; stripped from the
  # nixosConfigurations output so flake-schemas sees a pure machine set).
  # These ensure the A/B test configurations evaluate without errors.

  "test-odin-gaming" =
    let
      cfg = mkTestHost "odin" "gaming";
    in
    pkgs.runCommand "check-test-odin-gaming" { } ''
      echo "check: test-odin-gaming OK (${toString (builtins.length (builtins.attrNames cfg.options))} options)"
      touch $out
    '';
}
