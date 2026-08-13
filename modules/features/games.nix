{ lib, mkBool, ... }:
with lib;
{
  options.features = {
    games = {
      nethack.enable = mkBool "enable Nethack" true;
      dosemu.enable = mkBool "enable Dosemu" true;
      oss.enable = mkBool "enable OSS Games (SuperTux, Wesnoth, etc.)" false;
      steamProxy.enable = mkBool "route Steam traffic through local SOCKS5 proxy (proxychains LD_PRELOAD)" false;
      openmw.enable = mkBool "enable OpenMW (Morrowind Engine)" false;
    };

    emulators = {
      retroarch.enable = mkBool "enable RetroArch emulator" false;
      retroarch.full = mkBool "use retroarchFull with extended (unfree) cores" false;
      extra.enable = mkBool "enable Extra Emulators (PCSX2, DOSBox, etc.)" false;
    };
  };
}
