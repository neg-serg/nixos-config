##
# Module: system/kernel/minimize (stub)
# Purpose: Placeholder for future kernel minimization.
# The NixOS kernel config system (generate-config.pl) rejects options whose
# Kconfig dependencies aren't met ("unused option" errors). Full aggressive
# minimization requires bypassing this via custom kernel config.
#
# For now, use scripts/dev/kernel-localmodconfig.sh on a running system to
# generate a structuredExtraConfig block from loaded modules, then manually
# resolve any Kconfig dependency issues.
#
# Future: may use linuxManualConfig with a localmodconfig-derived .config.
{
  lib,
  config,
  ...
}: {
  # ZSTD kernel compression — fastest decompression + excellent compression ratio
  boot.kernelPatches = [{
    name = "kernel-zstd";
    patch = null;
    structuredExtraConfig = with lib.kernel; {
      KERNEL_ZSTD = yes;
    };
  }];
}
