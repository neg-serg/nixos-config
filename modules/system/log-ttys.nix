{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf concatStringsSep;
  cfg = config.features.system.logTtys;

  # Data-driven log TTY definitions
  logServices = {
    crit = {
      tty = "tty8";
      prio = "2";
      desc = "emerg..crit";
    };
    err = {
      tty = "tty10";
      prio = "3";
      desc = "errors";
    };
    warn = {
      tty = "tty11";
      prio = "4";
      desc = "warnings";
    };
    kernel = {
      tty = "tty12";
      desc = "kernel messages";
      filter = "_TRANSPORT=kernel";
    };
    auth = {
      tty = "tty13";
      desc = "auth messages";
      filter = "SYSLOG_FACILITY=4 + SYSLOG_FACILITY=10";
    };
    systemd = {
      tty = "tty14";
      desc = "systemd messages";
      filter = "_PID=1";
    };
    network = {
      tty = "tty15";
      desc = "network daemons";
    };
    full = {
      tty = "tty16";
      prio = "7";
      desc = "all messages";
    };
  };

  # amdgpu prints "Overdrive is enabled, please disable it..." at KERN_CRIT on
  # every boot while the overdrive bit (0x4000) is set in amdgpu.ppfeaturemask
  # (hosts/odin/hardware.nix). That bit must stay enabled for CoreCtrl UV/OC,
  # the kernel cannot suppress a single message, and journald's LogFilterPatterns
  # only applies to unit messages — so drop the line from the TTY viewers here.
  # journalctl --grep is PCRE2 (negative lookahead); "^..." anchoring keeps all
  # other messages matching so only that one line is filtered out.
  suppressOdNotice = "-g \"^(?!.*Overdrive is enabled).*\"";

  mkLogService =
    name:
    {
      tty,
      prio ? null,
      desc,
      filter ? null,
    }:
    mkIf (cfg.${name}.enable or false) {
      systemd.services."log-${name}" = {
        description = "Journal viewer: ${desc} on ${tty}";
        after = [ "systemd-journald.service" ];
        requires = [ "systemd-journald.service" ];
        unitConfig = {
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };
        serviceConfig = {
          ExecStart =
            if name == "network" then
              concatStringsSep " " (
                [
                  "${lib.getExe' pkgs.systemd "journalctl"}"
                  "-f"
                  "-o"
                  "short-monotonic"
                ]
                ++ map (u: "-u ${u}") cfg.networkUnits
              )
            else
              "${lib.getExe' pkgs.systemd "journalctl"} -f${if prio != null then " -p ${prio}" else ""}${
                if filter != null then " ${filter}" else ""
              } -o short-monotonic ${suppressOdNotice}";
          StandardOutput = "tty";
          TTYPath = "/dev/${tty}";
          TTYReset = true;
          Restart = "always";
          RestartSec = 5;
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
