{
  pkgs,
  lib,
  config,
  ...
}:
with lib; {
  config = {
    assertions = [
      {
        assertion = (! config.features.emulators.retroarch.full) || (builtins.hasAttr "retroarch-full" pkgs);
        message = "RetroArch full mode enabled but pkgs.\"retroarch-full\" is not available on this system.";
      }
    ];
    home.packages = config.lib.neg.pkgsList (
      [
        pkgs.pcem # emulator for ibm pc and clones
        pkgs.pcsx2 # ps2 emulator
      ]
      ++ (
        if config.features.emulators.retroarch.full
        then [pkgs."retroarch-full"] # RetroArch with full core set
        else [pkgs.retroarch] # RetroArch with free cores only
      )
    ); # frontend (full|free cores)
  };
}
