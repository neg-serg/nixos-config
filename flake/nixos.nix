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
    inputs.sops-nix.nixosModules.sops
    inputs.pleamar-config.nixosModules.default
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
  # Excluded: appimage (no trantor usage).
  excludedDomains = [
    "appimage"
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

in
{
  # Explicit contract: `configurations` is the pure machine set (flake-schemas
  # friendly); test-only configurations are not exported.
  configurations = {
    trantor = mkHost "trantor";
  };
  # `mkSpecialArgs` is exported so flake/checks.nix builds its evalModules stub
  # from the same arguments the real hosts use (it used to keep a drifting copy).
  inherit mkSpecialArgs;
}
