{lib, ...}:
with lib; let
  mkBool = desc: default: (lib.mkEnableOption desc) // {inherit default;};
in {
  options.features = {
    games = {
      enable = mkBool "enable Games stack" true;
      nethack.enable = mkBool "enable Nethack" true;
      dosemu.enable = mkBool "enable Dosemu" true;
    };

    emulators = {
      retroarch.full = mkBool "use retroarchFull with extended (unfree) cores" false;
    };
  };
}
