{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  guiEnabled = config.features.gui.enable or true;
  hyprWinList = pkgs.writeShellApplication {
    name = "hypr-win-list";
    runtimeInputs = [
      pkgs.python3
      pkgs.wl-clipboard
      pkgs.hyprland
    ];
    text =
      let
        tpl = builtins.readFile (
          inputs.self + "/modules/user/nix-maid/scripts/hypr/hypr-win-list.py"
        );
      in
      ''
                     exec python3 <<'PY'
        ${tpl}
        PY
      '';
  };
in
{
  config = lib.mkIf guiEnabled {
    environment.systemPackages = [
      hyprWinList
      inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system}
      pkgs.hyprcursor
      pkgs.hypridle
      pkgs.hyprlandPlugins.hy3
      pkgs.hyprpicker
      pkgs.hyprpolkitagent
      pkgs.hyprprop
      pkgs.hyprutils
      pkgs.pyprland
    ];
  };
}
