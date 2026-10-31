#
# Kernel module layout and attack-surface trimming
# (moved out of the docs tree; keep it in sync with the code it describes)
#
#
# - params: kernel cmdline and packaging — `modules/system/kernel/params.nix`.
# - sysctl: network/security sysctls in `modules/system/kernel/sysctl.nix`.
# - localmodconfig: kernel size reduction in `modules/system/kernel/localmodconfig.nix`
#   (`minimize.nix` was removed in 62e6d590).
# - Attack-surface trim: `modules/system/kernel/overlay.config` H19 removes drivers for hardware this
#   host does not have (legacy SATA/USB host controllers, vendor Bluetooth helpers, TV/radio/ SDR
#   tuners and IR, Intel platform glue, NVMe in-band authentication, the Intel KVM flavour, the FTP
#   conntrack helpers); H20 fixes three `base.config` lines kconfig rejects. The built kernel ships
#   209 modules instead of 258, and the initrd module list in `modules/system/boot.nix` no longer
#   names the removed ones.
# - Feature toggles: tune via `profiles.performance.*` and `profiles.security.*`; params derive from
#   these.
#
# ## PREEMPT_RT
#
# - Toggle: `profiles.performance.preemptRt.enable = true;`
# - Mode: `profiles.performance.preemptRt.mode = "auto" | "in-tree" | "rt";`
#   - `auto`: use in-tree `CONFIG_PREEMPT_RT` on kernels >= 6.12, otherwise switch to
#     `linuxPackages_rt`.
#   - `in-tree`: force enabling `CONFIG_PREEMPT_RT` on the current kernel package (no package switch).
#   - `rt`: switch kernel package to `pkgs.linuxPackages_rt` explicitly.
#
# Note: extra out-of-tree modules (e.g., `amneziawg`) are pulled from the selected
# `boot.kernelPackages` when available.
#
# ## Kernel source
#
# - `localmodconfig.nix` builds the minimized kernel from the stable point release of the 7.3
#   series (7.3.1, tarball pinned by hash from kernel.org) with this host's reduced `.config`.
# - ZFS is built with `--enable-linux-experimental` plus four 7.3 API backports: zfs 2.4.4
#   declares support only through kernel 7.2 (`kernelMaxSupportedMajorMinor` in nixpkgs'
#   `zfs/2_4.nix`), but the ZFS root has to stay mountable on 7.3.
#
# ## Debug/Profiling (optional)
#
# - Memory allocation profiling (6.10+):
#   `profiles.debug.memAllocProfiling.{enable,compileSupport,enabledByDefault,debugChecks}`.
# - perf data-type profiling (6.8+):
#   `profiles.debug.perfDataType.{enable,installTools,enableKernelBtf}`.
#   - These options may rebuild the kernel when enabling related `CONFIG_*` symbols.

{ neg, ... }:
{
  imports = neg.importDir { dir = ./.; };
}
