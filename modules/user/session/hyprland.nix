{
  inputs,
  pkgs,
  ...
}:
let
  hyprWinList = pkgs.writeShellApplication {
    # helper to list Hypr windows through rofi
    name = "hypr-win-list";
    runtimeInputs = [
      pkgs.python3 # embed interpreter so the script ships zero deps
      pkgs.wl-clipboard # pipe clipboard ops without relying on system PATH
      pkgs.hyprland # hyprctl command for window management
    ];
    text =
      let
        tpl = builtins.readFile (inputs.self + "/modules/user/nix-maid/scripts/hypr/hypr-win-list.py");
      in
      ''
                     exec python3 <<'PY'
        ${tpl}
        PY
      '';
  };
in
{
  environment.systemPackages = [
    # -- Hyprland --
    hyprWinList # injects rust-based win switcher bound in Hypr
    inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system} # run-or-raise for Hyprland
    pkgs.hyprcursor # modern cursor theme format for Hyprland
    pkgs.hypridle # idle daemon for Hyprland sessions
    pkgs.hyprlandPlugins.hy3 # tiling plugin for Hyprland
    pkgs.hyprpicker # color picker for Wayland/Hyprland
    pkgs.hyprpolkitagent # Wayland-friendly polkit agent
    pkgs.hyprprop # Hyprland property helper (xprop-like)
    pkgs.hyprutils # assorted Hyprland utilities
    pkgs.pyprland # Hyprland plugin/runtime helper
  ];
}
