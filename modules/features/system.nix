{ lib, config, ... }:
let
  cfg = config.features.system.logTtys;
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.system.logTtys = {
    enable = mkBool "Per-TTY log classification (journalctl viewers on tty8,tty10-tty16)" true;
    crit.enable = mkBool "CRIT log viewer on tty8 (emerg..crit)" true;
    err.enable = mkBool "ERR log viewer on tty10 (errors)" true;
    warn.enable = mkBool "WARN log viewer on tty11 (warnings)" true;
    kernel.enable = mkBool "KERNEL log viewer on tty12 (kernel messages)" true;
    auth.enable = mkBool "AUTH log viewer on tty13 (auth messages)" true;
    systemd.enable = mkBool "SYSTEMD log viewer on tty14 (systemd messages)" true;
    network.enable = mkBool "NETWORK log viewer on tty15 (network daemons)" true;
    full.enable = mkBool "FULL log viewer on tty16 (all messages)" true;
    networkUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "NetworkManager.service" "sshd.service" "tailscaled.service" "nftables.service" ];
      description = "Systemd units to monitor on tty15 (network TTY). Override per-host.";
    };
  };
}
