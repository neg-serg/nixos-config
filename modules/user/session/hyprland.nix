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
    name = "hypr-win-list"; # Hyprland window list via vicinae
    runtimeInputs = [
      pkgs.python3 # Python interpreter
      pkgs.wl-clipboard # clipboard manager for Wayland
      pkgs.hyprland # dynamic tiling Wayland compositor
    ];
    text =
      let
        tpl = builtins.readFile (
          inputs.self # flake self-reference
          + "/modules/user/nix-maid/scripts/hypr/hypr-win-list.py" # hypr-win-list script
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
      hyprWinList # Hyprland window list via vicinae
      inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system} # run-or-raise for Hyprland
      pkgs.hyprcursor # modern cursor theme format for Hyprland
      pkgs.hypridle # idle daemon for Hyprland
      pkgs.hyprpicker # color picker for Wayland/Hyprland
      pkgs.hyprpolkitagent # Wayland-friendly polkit agent
      pkgs.hyprprop # Hyprland property helper
      pkgs.hyprutils # assorted Hyprland utilities
    ];
  };
}
