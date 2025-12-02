{
  lib,
  config,
  ...
}:
with lib; let
  presets = import ../../../modules/features-data/unfree-presets.nix;
  cfg = config.features.allowUnfree or {};
in {
  config = {
    # If user didn't explicitly set .allowed, derive from preset + extra
    features.allowUnfree.allowed = mkDefault (presets.${cfg.preset or "desktop"} ++ (cfg.extra or []));
  };
}
