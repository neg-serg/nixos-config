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
    && (config.features.dev.ai.openagentscontrol.enable or false);
in
lib.mkIf enable {
  environment.systemPackages = [
    pkgs.neg.openagentscontrol # AI agent framework for plan-first development (agents + contexts for OpenCode)
  ];
}
