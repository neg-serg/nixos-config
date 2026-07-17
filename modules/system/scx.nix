# SCX (sched_ext) BPF scheduler service.
#
# Runs a userspace BPF scheduler via systemd to replace CFS on selected workloads.
# scx_lavd is recommended for X3D (dual-CCD, V-Cache aware).
# Requires: kernel with CONFIG_SCHED_CLASS_EXT=y (>= 6.12 built-in).
# Conflicts: isolcpus (kernel CPU isolation). SCX must see all CPUs.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.features.optimization.scx;
  schedBin = "${lib.getBin pkgs.scx.rustscheds}/bin/${cfg.scheduler}";
in
{
  options.features.optimization.scx = {
    enable = lib.mkEnableOption "SCX BPF scheduler (replaces CFS)";

    scheduler = lib.mkOption {
      type = lib.types.enum [
        "scx_beerland"
        "scx_bpfland"
        "scx_cake"
        "scx_chaos"
        "scx_cosmos"
        "scx_flash"
        "scx_flow"
        "scx_lavd"
        "scx_layered"
        "scx_mitosis"
        "scx_p2dq"
        "scx_pandemonium"
        "scx_rlfifo"
        "scx_rustland"
        "scx_rusty"
        "scx_tickless"
      ];
      default = "scx_lavd";
      description = ''
        SCX scheduler to run. scx_lavd is recommended for X3D gaming:
        it detects dual-CCD topology and favours the V-Cache CCD for
        latency-sensitive tasks.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # scx schedulers need the sched_ext kernel feature;
    # ensure the BPF JIT is enabled.
    boot.kernel.sysctl = {
      "kernel.bpf_stats_enabled" = false;
    };

    systemd.services.scx = {
      description = "SCX BPF scheduler (${cfg.scheduler})";
      documentation = [ "https://github.com/sched-ext/scx" ];
      after = [ "multi-user.target" ];
      wants = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = schedBin;
        Restart = "on-failure";
        RestartSec = "5s";
        # Needs CAP_SYS_ADMIN + CAP_BPF for BPF prog load,
        # CAP_SYS_NICE for scheduler ops.
        AmbientCapabilities = [ "CAP_SYS_ADMIN" "CAP_BPF" "CAP_SYS_NICE" ];
        CapabilityBoundingSet = [ "CAP_SYS_ADMIN" "CAP_BPF" "CAP_SYS_NICE" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        # Keep /sys accessible for CPU topology discovery.
        ReadWritePaths = [ "/sys" ];
        ProtectProc = "invisible";
      };
    };
  };
}
