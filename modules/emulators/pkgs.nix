{
  lib,
  config,
  pkgs,
  ...
}: let
  funEnabled = config.features.fun.enable or false;
  retroarchFull = config.features.emulators.retroarch.full or false;
  retroarchAvailable = builtins.hasAttr "retroarch-full" pkgs;
  retroarchPkg =
    if retroarchFull && retroarchAvailable
    then pkgs."retroarch-full"
    else pkgs.retroarch;
  packages = [
    pkgs.dosbox # DOS emulator
    pkgs.dosbox-staging # modernized DOSBox fork with better latency
    pkgs.dosbox-x # DOSBox fork focused on historical accuracy
    pkgs.pcem # IBM PC emulator
    pkgs.pcsx2 # PS2 emulator
    retroarchPkg # RetroArch frontend (full build when available)
  ];
in {
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = (! retroarchFull) || retroarchAvailable;
          message = "features.emulators.retroarch.full enabled but pkgs.\"retroarch-full\" is unavailable on this platform.";
        }
      ];
    }
    (lib.mkIf funEnabled {
      environment.systemPackages = lib.mkAfter packages;
    })
  ];
}
