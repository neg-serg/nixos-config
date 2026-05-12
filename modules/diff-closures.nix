{
  config,
  lib,
  ...
}:
let
  cfg = config.diffClosures;
in
{
  options.diffClosures = {
    enable = lib.mkEnableOption "Show diff-closures during system activation";
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.diffClosures.text = ''
      if [ -d "/run/current-system" ]; then
        echo -e "\e[1mChanges:\e[0m"
        ${config.nix.package}/bin/nix --experimental-features nix-command store diff-closures /run/current-system $systemConfig || echo "Error: $?"
        echo
      fi
    '';
  };
}
