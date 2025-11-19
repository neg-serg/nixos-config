{lib, config, pkgs, ...}: let
  funEnabled = config.features.fun.enable or false;
  retroarchFull = config.features.emulators.retroarch.full or false;
  retroarchAvailable = builtins.hasAttr "retroarch-full" pkgs;
  retroarchPkg =
    if retroarchFull && retroarchAvailable
    then pkgs."retroarch-full"
    else pkgs.retroarch;
  packages =
    [
      pkgs.dosbox # DOS emulator
      pkgs.dosbox-staging
      pkgs.dosbox-x
      pkgs.pcem # IBM PC emulator
      pkgs.pcsx2 # PS2 emulator
      retroarchPkg
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
