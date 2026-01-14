{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features = {
    games = {
      enable = mkBool "enable Games stack" true;
      nethack.enable = mkBool "enable Nethack" true;
      dosemu.enable = mkBool "enable Dosemu" true;
      launchers = {
        prismlauncher.enable = mkBool "enable PrismLauncher" true;
        heroic.enable = mkBool "enable Heroic Launcher" true;
        lutris.enable = mkBool "enable Lutris" true;
      };
      oss.enable = mkBool "enable OSS Games (SuperTux, Wesnoth, etc.)" false;
      openmw.enable = mkBool "enable OpenMW (Morrowind Engine)" false;
    };

    emulators = {
      retroarch.enable = mkBool "enable RetroArch emulator" false;
      retroarch.full = mkBool "use retroarchFull with extended (unfree) cores" false;
      extra.enable = mkBool "enable Extra Emulators (PCSX2, DOSBox, etc.)" false;
    };
  };
}
