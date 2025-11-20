{
  lib,
  negPaths ? null,
  ...
}: let
  defaultHome = ../..;
  defaultRepo = defaultHome + "/..";
  defaultPackages = defaultRepo + "/packages";
  provided =
    if negPaths != null
    then negPaths
    else {
      hmConfigRoot = defaultHome;
      repoRoot = defaultRepo;
      packagesRoot = defaultPackages;
    };
in {
  options.neg = {
    hmConfigRoot = lib.mkOption {
      type = lib.types.path;
      default = provided.hmConfigRoot;
      description = "Absolute path to the Home Manager configuration tree (used for linking config assets).";
      example = "/etc/nixos/home";
    };
    repoRoot = lib.mkOption {
      type = lib.types.path;
      default = provided.repoRoot;
      description = "Absolute path to the repository root (parent of neg.hmConfigRoot by default).";
      example = "/etc/nixos";
    };
    packagesRoot = lib.mkOption {
      type = lib.types.path;
      default = provided.packagesRoot;
      description = "Absolute path to the packages/ directory.";
      example = "/etc/nixos/packages";
    };
  };
}
