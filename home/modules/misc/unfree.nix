{
  lib,
  config,
  ...
}:
with lib; let
  presets = import ./unfree-presets.nix;
  cfg = config.features.allowUnfree or {};
in {
  config = {
    # If user didn't explicitly set .allowed, derive from preset + extra
    features.allowUnfree.allowed = mkDefault (presets.${cfg.preset or "desktop"} ++ (cfg.extra or []));

    nixpkgs.config.allowUnfreePredicate = pkg: let
      name = pkg.pname or (builtins.parseDrvName (pkg.name or "")).name;
    in
      builtins.elem name config.features.allowUnfree.allowed;
  };
}
