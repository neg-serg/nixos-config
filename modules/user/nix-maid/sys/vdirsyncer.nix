{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.mail.vdirsyncer;
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        environment.systemPackages = [ pkgs.vdirsyncer ]; # synchronize calendars and contacts between diverse storage backends

        # Create the config from template
        sops.templates."vdirsyncer-config" = {
          content = ''
            [general]
            status_path = "~/.config/vdirsyncer/status/"

            [storage neg_contacts_local]
            type = "filesystem"
            path = "~/.config/vdirsyncer/contacts/"
            fileext = ".vcf"

            [pair neg_calendar]
            a = "neg_calendar_local"
            b = "neg_calendar_remote"
            collections = ["from a", "from b"]
            metadata = ["displayname", "color"]

            [storage neg_calendar_local]
            type = "filesystem"
            path = "~/.config/vdirsyncer/calendars/"
            fileext = ".ics"

            [storage neg_calendar_remote]
            type = "google_calendar"
            token_file = "~/.config/vdirsyncer/token_stuff"
            client_id = "${config.sops.placeholder.vdirsyncer_google_client_id}"
            client_secret = "${config.sops.placeholder.vdirsyncer_google_client_secret}"
          '';
          owner = "neg";
          mode = "0600";
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
            ExecStartPre = "${lib.getExe pkgs.vdirsyncer} metasync"; # Synchronize calendars and contacts
            ExecStart = "${lib.getExe pkgs.vdirsyncer} sync"; # Synchronize calendars and contacts
          };
        };

        systemd.user.timers.vdirsyncer = {
          description = "Vdirsyncer synchronization timer";
          timerConfig = {
            OnBootSec = "2m";
            OnUnitActiveSec = "5m";
            Unit = "vdirsyncer.service";
          };
          wantedBy = [ "timers.target" ];
        };
      }

      (n.mkHomeFiles {
        # Link the template to ~/.config/vdirsyncer/config
        ".config/vdirsyncer/config".source = config.sops.templates."vdirsyncer-config".path;
      })
    ]
  );
}
