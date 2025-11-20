{
  lib,
  config,
  inputs,
  ...
} @ args:
with lib; let
  mainUser = config.users.main.name or "neg";
  defaultRoot = "/home/${mainUser}/games/UnrealEngine";
  hmFeatures = import (inputs.self + "/home/modules/features.nix") args;
  unrealOption = {
    enable = (mkEnableOption "enable Unreal Engine 5 tooling") // {default = false;};
    root = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Checkout directory for Unreal Engine sources. Defaults to "${defaultRoot}".
      '';
      example = "/mnt/storage/UnrealEngine";
    };
    repo = mkOption {
      type = types.str;
      default = "git@github.com:EpicGames/UnrealEngine.git";
      description = "Git URL used by ue5-sync (requires EpicGames/UnrealEngine access).";
    };
    branch = mkOption {
      type = types.str;
      default = "5.4";
      description = "Branch or tag to sync from the Unreal Engine repository.";
    };
    useSteamRun = mkOption {
      type = types.bool;
      default = true;
      description = "Wrap Unreal Editor launch via steam-run to provide FHS runtime libraries.";
    };
  };
in {
  options = lib.recursiveUpdate hmFeatures.options {features.dev.unreal = unrealOption;};
  config = hmFeatures.config;
}
