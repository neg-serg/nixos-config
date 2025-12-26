# Games Module
#
# Main entry point for gaming configuration.
# Imports submodules for launchers, performance, and VR.
{lib, ...}: {
  imports = [
    ./launchers.nix
    ./performance.nix
    ./vr.nix
  ];

  options.profiles.games = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the gaming stack (Steam, Gamescope wrappers, MangoHud, hardware rules).";
    };
    autoscaleDefault = lib.mkEnableOption "Enable autoscale heuristics by default for gamescope-targetfps.";
    targetFps = lib.mkOption {
      type = lib.types.int;
      default = 240;
      description = "Default target FPS used when autoscale is enabled globally or TARGET_FPS is unset.";
      example = 240;
    };
    nativeBaseFps = lib.mkOption {
      type = lib.types.int;
      default = 240;
      description = "Estimated FPS at native resolution used as baseline for autoscale heuristic.";
      example = 240;
    };
  };
}
