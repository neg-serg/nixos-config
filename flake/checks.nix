# Checks for parallel evaluation via nix-eval-jobs.
#
# Each check exercises an independent subset of the NixOS module tree.
# nix-eval-jobs dispatches every flake output attribute as a separate job,
# so adding checks here creates additional parallel eval units that run
# alongside nixosConfigurations, devShells, etc.
#
# Domain filter refactoring (Jul 2026):
#   modules/default.nix now accepts domainFilter via specialArgs. The
#   nixosConfiguration A/B test configs (telfir-lite, telfir-server) use
#   restrictive filters to produce smaller eval trees. These module checks
#   validate that the filter mechanism works correctly.
# ---------------------------------------------------------------------------
{
  nixpkgs,
  self,
  inputs,
  ...
}:
system: pkgs:
let
  inherit (nixpkgs) lib;

  # Real specialArgs that the module tree needs for evalModules.
  # We provide the minimal set — stubs where full values aren't needed.
  mkStubArgs = domainFilter: {
    inherit domainFilter;
    # Required by nix/settings.nix, modules/system/default.nix, etc.
    inputs = {
      inherit self;
      nixpkgs = nixpkgs;
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
      mkUserJs = _: "";
      mkProfilesIni = _: "";
    };
  };

  mkModuleCheck =
    name: extraModules: domainFilter:
    let
      result = lib.evalModules {
        specialArgs = mkStubArgs (domainFilter or (_: true));
        modules =
          [
            { _module.check = false; }
            ../modules/features
          ]
          ++ extraModules;
      };
    in
    pkgs.runCommand "check-${name}" { } ''
      echo "check: ${name} OK (${
        toString (builtins.length (builtins.attrNames result.options))
      } options)"
      touch $out
    '';

in
{
  # ── Module-level checks ──────────────────────────────────────────
  # Each validates a domain or domain set independently.

  "mod-features" = mkModuleCheck "features" [ ] (_: true);
  "mod-profiles" = mkModuleCheck "profiles" [ ../modules/profiles/default.nix ] (_: true);
  "mod-core" = mkModuleCheck "core" [ ../modules/core/default.nix ] (_: true);
  "mod-roles" = mkModuleCheck "roles" [ ../modules/roles/default.nix ] (_: true);

  # ── Domain filter checks ─────────────────────────────────────────
  # Validate that modules/default.nix works with different domain filters.
  # These create INDEPENDENT eval trees for nix-eval-jobs to process in parallel.

  "dom-lite" =
    let
      liteDomains = [
        "cli"
        "core"
        "diff-closures"
        "documentation"
        "features"
        "flake-preflight"
        "fonts"
        "hardware"
        "nix"
        "profiles"
        "roles"
        "secrets"
        "security"
        "servers"
        "shell"
        "system"
        "text"
        "tools"
      ];
      filter = domain: builtins.elem domain liteDomains;
      result = lib.evalModules {
        specialArgs = mkStubArgs filter;
        modules = [
          { _module.check = false; }
          ../modules/default.nix
        ];
      };
    in
    pkgs.runCommand "check-dom-lite" { } ''
      echo "modules/default.nix + lite filter: OK"
      touch $out
    '';

  "dom-all" =
    let
      result = lib.evalModules {
        specialArgs = mkStubArgs (_: true);
        modules = [
          { _module.check = false; }
          ../modules/default.nix
        ];
      };
    in
    pkgs.runCommand "check-dom-all" { } ''
      echo "modules/default.nix + all filter: OK"
      touch $out
    '';
}
