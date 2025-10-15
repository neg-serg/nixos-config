{ config, lib, pkgs, ... }:
let
  cfg = config.user.session.plasma;
in
{
  options.user.session.plasma = {
    enableX11 = lib.mkEnableOption "Install KDE Plasma (enable desktopManager.plasma6 and X11 support) without enabling a display manager";
    uwsmOption = lib.mkEnableOption "Expose Plasma (Wayland) as a UWSM-selectable session (does not affect Hyprland)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enableX11 {
      # Provide X11 stack and Plasma desktop (no DM enabled here)
      services.xserver.enable = true;
      # Ensure the Xorg session uses the AMDGPU driver
      services.xserver.videoDrivers = [ "amdgpu" ];
      services.desktopManager.plasma6.enable = true;

      # Useful extras for a more complete Plasma experience when launched manually
      environment.systemPackages = with pkgs; [
        kdePackages.kde-cli-tools
        kdePackages.kio-extras
      ];
    })

    (lib.mkIf cfg.uwsmOption {
      # Ensure uwsm CLI is available; Hyprland's module may already bring it,
      # but we add it explicitly without changing Hyprland config.
      environment.systemPackages = [ pkgs.uwsm ];
      # No extra wiring is needed: uwsm discovers Plasma via wayland-sessions/plasma.desktop
      # provided by plasma-workspace when plasma6 is enabled. This adds a selectable
      # "plasma" entry for `uwsm start`/`uwsm select`, without touching Hyprland.
    })
  ];
}
