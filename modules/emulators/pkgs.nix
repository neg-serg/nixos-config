{
  lib,
  config,
  pkgs,
  ...
}:
let
  funEnabled = config.features.fun.enable or false;
  retroarchFull = config.features.emulators.retroarch.full or false;
  retroarchAvailable = builtins.hasAttr "retroarch-full" pkgs;
  retroarchPkg =
    if retroarchFull && retroarchAvailable then pkgs."retroarch-full" else pkgs.retroarch; # Multi-platform emulator frontend for libretro cores
  retroarchEnabled = config.features.emulators.retroarch.enable or false;
  extraEnabled = config.features.emulators.extra.enable or false;

  extraPackages = [
    pkgs.dosbox # DOS emulator
    pkgs.dosbox-staging # modernized DOSBox fork with better latency
    pkgs.dosbox-x # DOSBox fork focused on historical accuracy
    pkgs.pcem # IBM PC emulator
    pkgs.pcsx2 # PS2 emulator
  ];

  retroarchPackages = [
    pkgs.retroarch-assets # standard assets (fonts, icons, etc.)
    pkgs.retroarch-joypad-autoconfig # controller profiles
  ]
  ++ (lib.optionals retroarchEnabled [
    retroarchPkg # RetroArch frontend (full build when available)
  ]);
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = (!retroarchFull) || retroarchAvailable;
          message = "features.emulators.retroarch.full enabled but pkgs.\"retroarch-full\" is unavailable on this platform.";
        }
      ];
    }
    (lib.mkIf (funEnabled && extraEnabled) {
      environment.systemPackages = lib.mkAfter extraPackages;
    })
    (lib.mkIf (funEnabled && retroarchEnabled) {
      environment.systemPackages = lib.mkAfter retroarchPackages;
    })
  ];
}
