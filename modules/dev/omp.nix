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
    && (config.features.dev.ai.omp.enable or false);
in
lib.mkIf enable {
  environment.systemPackages = [
    pkgs.neg.omp # Oh My Pi (omp) — AI coding agent with LSP, DAP, subagents
  ];
}
