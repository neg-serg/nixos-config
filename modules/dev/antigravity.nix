{
  lib,
  config,
  pkgs,
  ...
}:
let
  enable =
    (config.features.dev.enable or false)
    && (config.features.dev.ai.enable or false)
    && (config.features.dev.ai.antigravity.enable or false);
in
lib.mkIf enable {
  environment.systemPackages = [
    pkgs.antigravity-manual # Google Antigravity agentic IDE (Manual Wrapper)
  ];
}
