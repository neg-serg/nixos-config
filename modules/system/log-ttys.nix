{ lib, config, pkgs, ... }:
let
  inherit (lib) mkIf concatStringsSep;
  cfg = config.features.system.logTtys;

  # Data-driven log TTY definitions
  logServices = {
    crit = { tty = "tty8";  prio = "2";  desc = "emerg..crit"; };
    err  = { tty = "tty10"; prio = "3";  desc = "errors"; };
    warn = { tty = "tty11"; prio = "4";  desc = "warnings"; };
    kernel = { tty = "tty12"; desc = "kernel messages"; filter = "_TRANSPORT=kernel"; };
    auth = { tty = "tty13"; desc = "auth messages";    filter = "SYSLOG_FACILITY=4 SYSLOG_FACILITY=10"; };
    systemd = { tty = "tty14"; desc = "systemd messages"; filter = "_PID=1"; };
    network = { tty = "tty15"; desc = "network daemons"; };
    full = { tty = "tty16"; prio = "7";  desc = "all messages"; };
  };

  mkLogService = name: { tty, prio ? null, desc, filter ? null }: mkIf (cfg.${name}.enable or false) {
    systemd.services."log-${name}" = {
      description = "Journal viewer: ${desc} on ${tty}";
      after = [ "systemd-journald.service" ];
      requires = [ "systemd-journald.service" ];
      serviceConfig = {
        ExecStart =
          if name == "network" then
            concatStringsSep " " (
              [ "${lib.getExe' pkgs.systemd "journalctl"}" "-f" "-o" "short-monotonic" ]
              ++ map (u: "-u ${u}") cfg.networkUnits
            )
          else
            "${lib.getExe' pkgs.systemd "journalctl"} -f${
              if prio != null then " -p ${prio}" else ""
            }${if filter != null then " ${filter}" else ""} -o short-monotonic";
        StandardOutput = "tty";
        TTYPath = "/dev/${tty}";
        TTYReset = true;
        Restart = "always";
        RestartSec = 5;
        StartLimitIntervalSec = 30;
        StartLimitBurst = 5;
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
in
{
  config = mkIf cfg.enable (
    lib.mkMerge (map (name: mkLogService name logServices.${name}) (builtins.attrNames logServices))
  );
}
