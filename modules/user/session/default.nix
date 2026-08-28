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

  # swayosd OSD: volume/brightness overlays used by both Hyprland and MangoWM
  # media binds (swayosd-client). Was invoked but never declared before.
  environment.systemPackages = [ pkgs.swayosd ];
  systemd.user.services.swayosd = {
    description = "SwayOSD on-screen display daemon";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe' pkgs.swayosd "swayosd-server"}";
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };
}
