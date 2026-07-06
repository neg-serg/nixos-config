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
    && (config.features.dev.ai.pi.enable or false);
in
lib.mkIf enable {
  environment.systemPackages = [
    pkgs.pi-coding-agent # AI coding agent CLI with read, bash, edit, write tools
  ];
}
