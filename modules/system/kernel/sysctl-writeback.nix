##
# Module: system/kernel/sysctl-writeback
# Purpose: Tune kernel writeback to reduce IO burst latency.
# Key options: profiles.performance.writeback.*
{
  lib,
  config,
  ...
}: let
  opts = import ../../../lib/opts.nix {inherit lib;};
in {
  options.profiles.performance.writeback = rec {
    enable = opts.mkEnableOption "Apply writeback sysctl tuning (reduces IO bursts).";
    dirtyBackgroundBytes = opts.mkIntOpt {
      default = 64 * 1024 * 1024; # 64 MiB
      description = "Background threshold (bytes) to start writeback.";
    };
    dirtyBytes = opts.mkIntOpt {
      default = 256 * 1024 * 1024; # 256 MiB
      description = "Threshold (bytes) to force writeback (limits burst).";
    };
    dirtyExpireCentisecs = opts.mkIntOpt {
      default = 3000; # 30s
      description = "Time (centiseconds) before dirty data is considered old.";
    };
    dirtyWritebackCentisecs = opts.mkIntOpt {
      default = 500; # 5s
      description = "Writeback period (centiseconds).";
    };
  };

  config = lib.mkIf (config.profiles.performance.writeback.enable or false) {
    boot.kernel.sysctl = {
      "vm.dirty_background_bytes" = config.profiles.performance.writeback.dirtyBackgroundBytes;
      "vm.dirty_bytes" = config.profiles.performance.writeback.dirtyBytes;
      "vm.dirty_expire_centisecs" = config.profiles.performance.writeback.dirtyExpireCentisecs;
      "vm.dirty_writeback_centisecs" = config.profiles.performance.writeback.dirtyWritebackCentisecs;
    };
  };
}
