{ lib, config, pkgs, ... }:
let
  inherit (lib) mkIf mkMerge concatStringsSep;
  cfg = config.features.system.logTtys;
in
{
  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.crit.enable {
      systemd.services.log-crit = {
        description = "Journal viewer: emerg..crit on tty8";
        after = [ "systemd-journald.service" ];
        requires = [ "systemd-journald.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/bin/journalctl -f -p 2 -o short-monotonic";
          StandardOutput = "tty";
          TTYPath = "/dev/tty8";
          TTYReset = true;
          Restart = "always";
          RestartSec = 5;
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    })
    (mkIf cfg.err.enable {
      systemd.services.log-err = {
        description = "Journal viewer: errors on tty10";
        after = [ "systemd-journald.service" ];
        requires = [ "systemd-journald.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/bin/journalctl -f -p 3 -o short-monotonic";
          StandardOutput = "tty";
          TTYPath = "/dev/tty10";
          TTYReset = true;
          Restart = "always";
          RestartSec = 5;
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    })
    (mkIf cfg.warn.enable {
      systemd.services.log-warn = {
        description = "Journal viewer: warnings on tty11";
        after = [ "systemd-journald.service" ];
        requires = [ "systemd-journald.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/bin/journalctl -f -p 4 -o short-monotonic";
          StandardOutput = "tty";
          TTYPath = "/dev/tty11";
          TTYReset = true;
          Restart = "always";
          RestartSec = 5;
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    })
    (mkIf cfg.kernel.enable {
      systemd.services.log-kernel = {
        description = "Journal viewer: kernel messages on tty12";
        after = [ "systemd-journald.service" ];
        requires = [ "systemd-journald.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/bin/journalctl -f _TRANSPORT=kernel -o short-monotonic";
          StandardOutput = "tty";
          TTYPath = "/dev/tty12";
          TTYReset = true;
          Restart = "always";
          RestartSec = 5;
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    })
    (mkIf cfg.auth.enable {
      systemd.services.log-auth = {
        description = "Journal viewer: auth messages on tty13";
        after = [ "systemd-journald.service" ];
        requires = [ "systemd-journald.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/bin/journalctl -f SYSLOG_FACILITY=4 SYSLOG_FACILITY=10 -o short-monotonic";
          StandardOutput = "tty";
          TTYPath = "/dev/tty13";
          TTYReset = true;
          Restart = "always";
          RestartSec = 5;
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    })
    (mkIf cfg.systemd.enable {
      systemd.services.log-systemd = {
        description = "Journal viewer: systemd messages on tty14";
        after = [ "systemd-journald.service" ];
        requires = [ "systemd-journald.service" ];
        serviceConfig = {
          # `_PID=1` = systemd-pid1 messages (unit lifecycle, targets, failures)
          ExecStart = "${pkgs.systemd}/bin/journalctl -f _PID=1 -o short-monotonic";
          StandardOutput = "tty";
          TTYPath = "/dev/tty14";
          TTYReset = true;
          Restart = "always";
          RestartSec = 5;
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    })
    (mkIf cfg.network.enable {
      systemd.services.log-network = mkIf (cfg.networkUnits != []) {
        description = "Journal viewer: network daemons on tty15";
        after = [ "systemd-journald.service" ];
        requires = [ "systemd-journald.service" ];
        serviceConfig = {
          ExecStart = concatStringsSep " " (
            [ "${pkgs.systemd}/bin/journalctl" "-f" "-o" "short-monotonic" ]
            ++ map (u: "-u ${u}") cfg.networkUnits
          );
          StandardOutput = "tty";
          TTYPath = "/dev/tty15";
          TTYReset = true;
          Restart = "always";
          RestartSec = 5;
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    })
    (mkIf cfg.full.enable {
      systemd.services.log-full = {
        description = "Journal viewer: all messages on tty16";
        after = [ "systemd-journald.service" ];
        requires = [ "systemd-journald.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/bin/journalctl -f -p 7 -o short-monotonic";
          StandardOutput = "tty";
          TTYPath = "/dev/tty16";
          TTYReset = true;
          Restart = "always";
          RestartSec = 5;
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    })
  ]);
}
