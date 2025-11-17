{
  lib,
  config,
  systemdUser,
  ...
}: {
  services = {
    udiskie = {
      enable = true;
      tray = "never";
    };
  };

  # Align the unit with our Wayland session and presets, similar to Flameshot.
  systemd.user.services.udiskie = lib.mkMerge [
    {
      Service = {
        Environment = ["QT_QPA_PLATFORM=wayland" "XDG_SESSION_TYPE=wayland"];
        Restart = "on-failure";
        RestartSec = 2;
      };
    }
    (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
  ];
}
