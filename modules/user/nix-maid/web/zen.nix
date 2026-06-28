{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.features.web.zen;
  webEnabled = config.features.web.enable or false;
  guiEnabled = config.features.gui.enable or false;
  zenProfileLink = "${config.users.users.neg.home}/.zen";
  zenProfileTarget = "${config.users.users.neg.home}/.config/zen";
in
{
  config = lib.mkIf (webEnabled && guiEnabled && (cfg.enable or false)) {
    environment.systemPackages = [
      pkgs.zen-browser # Zen Browser (Firefox-based; profile at ~/.zen -> ~/.config/zen)
    ];

    environment.sessionVariables = {
      MOZ_ENABLE_WAYLAND = "1";
      MOZ_DBUS_REMOTE = "1";
    };

    # Zen looks for profiles in ~/.zen/ per application.ini Profile=zen.
    # Actual profiles migrated manually to ~/.config/zen/.
    systemd.user.tmpfiles.rules = [
      "L+ ${zenProfileLink} - - - - ${zenProfileTarget}"
    ];
  };
}
