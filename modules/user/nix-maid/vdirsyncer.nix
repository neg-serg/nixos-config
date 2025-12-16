{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features.mail.vdirsyncer;
  filesRoot = ../../../home/files;
in
  lib.mkIf (cfg.enable or false) {
    environment.systemPackages = [pkgs.vdirsyncer];

    # Create the config from template
    sops.templates."vdirsyncer-config" = {
      content = builtins.readFile "${filesRoot}/vdirsyncer/config";
      owner = "neg";
      mode = "0600";
    };

    # Link the template to ~/.config/vdirsyncer/config
    users.users.neg.maid.file.home = {
      ".config/vdirsyncer/config".source = config.sops.templates."vdirsyncer-config".path;
    };

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${config.users.users.neg.home}/.config/vdirsyncer/calendars 0700 neg users -"
      "d ${config.users.users.neg.home}/.config/vdirsyncer/contacts 0700 neg users -"
      "d ${config.users.users.neg.home}/.local/state/vdirsyncer 0700 neg users -"
    ];

    # User service and timer
    systemd.user.services.vdirsyncer = {
      description = "Vdirsyncer synchronization service";
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${lib.getExe pkgs.vdirsyncer} metasync";
        ExecStart = "${lib.getExe pkgs.vdirsyncer} sync";
      };
    };

    systemd.user.timers.vdirsyncer = {
      description = "Vdirsyncer synchronization timer";
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "5m";
        Unit = "vdirsyncer.service";
      };
      wantedBy = ["timers.target"];
    };
  }
