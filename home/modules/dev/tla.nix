{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf (config.features.dev.tla.enable or false) {
  home.packages = with pkgs; [
    tlaplus
    tlaplusToolbox
    tlafmt
    # tlaps # Proof system if needed, but it's often heavy/complex to setup
  ];
}
