##
# Module: user/session/hypr-kdeconnect
# Purpose: xdg-desktop-portal RemoteDesktop backend for KDE Connect / Deskflow.
#   The Hyprland portal backend exposes screencast, screenshot and global
#   shortcuts, but not RemoteDesktop input, so remote pointer/keyboard from
#   KDE Connect never reaches the compositor. hypr-kdeconnect-fix implements
#   that one interface and injects events through zwlr_virtual_pointer_v1 and
#   zwp_virtual_keyboard_v1 (including the libei ConnectToEIS path KDE Connect
#   26.04+ prefers).
# Key options: features.gui.hyprKdeconnect.enable
# Dependencies: pkgs.hypr-kdeconnect-fix (packages/hypr-kdeconnect-fix),
#   xdg.portal config (modules/user/xdg.nix owns the rest of the routing).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  portalId = "hypr-kdeconnect";
in
lib.mkIf (config.lib.neg.enabled "gui.hyprKdeconnect") {
  xdg.portal = {
    # extraPortals does both halves of the wiring: it puts the package into
    # environment.systemPackages (so hypr-kdeconnect-portal is on PATH for the
    # --self-test-* checks) and its share/xdg-desktop-portal/portals onto the
    # frontend's XDG_DATA_DIRS, which is what registers the backend. The
    # D-Bus activation file rides along in the same package.
    extraPortals = [ pkgs.hypr-kdeconnect-fix ];
    # Route RemoteDesktop only: file chooser, screenshot, screencast and
    # global shortcuts stay with the hyprland/gtk backends.
    config = {
      common."org.freedesktop.impl.portal.RemoteDesktop" = [ portalId ];
      hyprland."org.freedesktop.impl.portal.RemoteDesktop" = [ portalId ];
    };
  };

  # Upstream installs the unit to share/systemd/user, while systemd.packages
  # only links lib/systemd/user — so the unit is declared here instead of
  # relying on the XDG_DATA_DIRS unit lookup. Fields mirror upstream
  # data/hypr-kdeconnect-portal.service.in; the D-Bus name is what the
  # .service file activates, hence Type/BusName.
  systemd.user.services.hypr-kdeconnect-portal = config.lib.neg.systemdUser.mkUserService {
    presets = [ "restartOnFailure" ];
    description = "KDE Connect RemoteDesktop portal backend for virtual-input Wayland compositors";
    partOf = [ "xdg-desktop-portal.service" ];
    serviceConfig = {
      Type = "dbus";
      BusName = "org.freedesktop.impl.portal.desktop.hypr_kdeconnect";
      ExecStart = lib.getExe' pkgs.hypr-kdeconnect-fix "hypr-kdeconnect-portal";
      RestartSec = "1s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
    };
  };
}
