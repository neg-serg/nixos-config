{
  lib,
  config,
}:
with lib; let
  devEnabled = config.features.dev.enable or false;
  hackEnabled = config.features.hack.enable or false;
  enabled = devEnabled && hackEnabled;
  excludePkgs = config.features.excludePkgs or [];
  pnameOf = pkg: (pkg.pname or (builtins.parseDrvName (pkg.name or "")).name);
  filterExcluded = pkgList: filter (pkg: !(elem (pnameOf pkg) excludePkgs)) pkgList;
  notBroken = pkg: !((pkg.meta or {}).broken or false);
  filterPackages = pkgList: filter notBroken (filterExcluded pkgList);
  mkGroupPackages = flags: groups:
    concatLists (
      mapAttrsToList (
        name: pkgList:
          if attrByPath [name] false flags
          then pkgList
          else []
      )
      groups
    );
in {
  inherit enabled filterPackages mkGroupPackages;
}
