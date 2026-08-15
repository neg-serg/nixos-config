{
  pkgs,
  lib,
  ...
}:
{
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix" && lib.hasSuffix ".nix" n)
    |> builtins.map (n: ./. + "/${n}");

  programs.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
  };

  services = {
    accounts-daemon.enable = true;
    dbus.implementation = "broker";
    libinput.enable = true;
    ratbagd.enable = true;
  };
}
