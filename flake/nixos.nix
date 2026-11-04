{
  inputs,
  nixpkgs,
  self,
  pkgs,
  filteredSource,
  ...
}:
let
  inherit (nixpkgs) lib;
  hostsDir = ../hosts;

  linuxSystem = "x86_64-linux";
  locale = "en_US.UTF-8";
  timeZone = "Europe/Moscow";

  commonModules = [
    ../init.nix
    inputs.determinate.nixosModules.default
    inputs.nix-flatpak.nixosModules.nix-flatpak
    inputs.sops-nix.nixosModules.sops
    ../modules/system/disabled-modules.nix
  ];

  # -------------------------------------------------------------------------
  # Domain filter — enables parallel eval by skipping unused module domains.
  # Each domain maps to a subdirectory under modules/. The filter
  # `domainFilter :: string -> bool` is passed via specialArgs to every module.
  # modules/default.nix uses it to conditionally import domain aggregators.
  # -------------------------------------------------------------------------

  # One domain = one directory under modules/ with a default.nix; the walk is
  # modules/default.nix's importDir. Read the list from the tree instead of
  # keeping it by hand: a new directory that nobody added to a hand-written list
  # would simply not be imported, and the module system reports that as a
  # missing option only when something references it (never, for a dead domain).
  allDomains = builtins.attrNames (
    lib.filterAttrs (
      name: type: type == "directory" && builtins.pathExists (../modules + "/${name}/default.nix")
    ) (builtins.readDir ../modules)
  );

  # Trantor: full desktop minus domains with zero trantor references.
  # Excluded: appimage (no trantor usage), apps (obsidian via flatpak).
  excludedDomains = [
    "appimage"
    "apps"
  ];
  trantorDomains = builtins.filter (d: !(builtins.elem d excludedDomains)) allDomains;

  mkDomainFilter = domains: name: builtins.elem name domains;

  # Shared specialArgs for all NixOS configurations.
  mkSpecialArgs = {
    inherit
      locale
      timeZone
      self
      inputs
      filteredSource
      ;
    iosevkaNeg = inputs.iosevka-neg.packages.${linuxSystem};

    # Repo root as a real path literal (not a string): used by
    # config.lib.neg.path to copy individual repo files into the store with
    # proper closure dependencies.
    repoRoot = ../.;

    # Default: import all domains (full workstation).
    domainFilter = mkDomainFilter allDomains;
    opts = import (self + "/lib/opts.nix") { inherit lib; };

    # Structural helpers — single source: lib/neg-helpers.nix
    # (also imported by flake/checks.nix instead of stubs).
    neg = import (self + "/lib/neg-helpers.nix");
  };

  mkHost =
    name:
    lib.nixosSystem {
      inherit pkgs;
      specialArgs = mkSpecialArgs // {
        domainFilter = mkDomainFilter (if name == "trantor" then trantorDomains else allDomains);
      };
      modules = commonModules ++ [ (import ((builtins.toString hostsDir) + "/" + name)) ];
    };

  # A/B test configurations: same base host but WITH ONLY THE TEST PROFILE ACTIVE.
  # This replaces the base profiles entirely (via mkForce) so the comparison is clean:
  # base config vs single-profile test config, no priority conflicts.
  #
  # NEVER evaluated during normal `nixos-rebuild switch --flake .#trantor`.
  # Evaluated by flake/checks.nix (test-trantor-*) via the exported mkTestHost.
  mkTestHost =
    baseName: testProfile:
    lib.nixosSystem {
      inherit pkgs;
      # Same domain filter as mkHost: a test host must evaluate the configuration
      # the real host runs, not the all-domains superset (trantor excludes
      # appimage/apps, so importing them here hid real eval breakage).
      specialArgs = mkSpecialArgs // {
        domainFilter = mkDomainFilter (if baseName == "trantor" then trantorDomains else allDomains);
      };
      modules =
        commonModules
        ++ [ (import ((builtins.toString hostsDir) + "/" + baseName)) ]
        ++ [
          # mkForce: replace host profiles entirely so the test profile is the sole active one
          { features.profiles = lib.mkForce [ testProfile ]; }
        ];
    };

in
{
  # Explicit contract: `configurations` is the pure machine set (flake-schemas
  # friendly), `mkTestHost` is the A/B test builder consumed by flake/checks.nix.
  configurations = {
    trantor = mkHost "trantor";
  };
  # `mkSpecialArgs` is exported so flake/checks.nix builds its evalModules stub
  # from the same arguments the real hosts use (it used to keep a drifting copy).
  inherit mkSpecialArgs mkTestHost;
}
