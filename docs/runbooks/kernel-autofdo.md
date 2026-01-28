# Kernel AutoFDO Optimization Guide

This guide describes how to optimize the Linux kernel using AutoFDO (Auto-Feedback-Directed
Optimization). This technique allows building a kernel optimized for your specific workload using
production-collected profiles.

## Prerequisites

1. **Clang-built Kernel**: AutoFDO requires the kernel to be built with Clang.
1. **Perf Support**: Your CPU must support required PMU events (LBR on Intel, BRS/amd_lbr_v2 on
   AMD).

## Workflow

### 1. Preparation (Instrumented Build)

First, you need to build the kernel with AutoFDO support enabled but without a profile. This ensures
the kernel has the necessary build flags to match the future profile.

In your host configuration (e.g., `hosts/telfir/hardware.nix`):

```nix
boot.kernel.autofdo.enable = true;
# boot.kernel.autofdo.profile = null; # Ensure this is null
```

Apply the configuration and reboot into the new kernel.

### 2. Profiling (Data Collection)

Run the workload you want to optimize for (e.g., compile a large project, run a benchmark, or just
normal usage) while recording with `perf`.

**Note**: The `-c` (count) parameter should be a prime number (e.g., 500009) to avoid lockstep
sampling bias.

#### standard (Intel capable of LBR)

```bash
perf record -b -e BR_INST_RETIRED.NEAR_TAKEN:k -a -N -c 500009 -o perf.data -- sleep 120
```

(Replace `sleep 120` with your actual workload command or just let it run for a while)

#### AMD (Zen3 with BRS / Zen4)

Check if supported: `grep -E "brs|amd_lbr_v2" /proc/cpuinfo`

```bash
perf record --pfm-events RETIRED_TAKEN_BRANCH_INSTRUCTIONS:k -a -N -b -c 500009 -o perf.data -- sleep 120
```

### 3. Profile Generation

Convert the raw `perf.data` into an AutoFDO profile using `create_llvm_prof` (from `autofdo`
package) or `llvm-profgen` (from LLVM).

You need the `vmlinux` binary corresponding to your CURRENT running kernel. On NixOS, you can
usually find it in `/run/current-system/kernel/vmlinux` (if uncompressed) or you might need to
extract it. However, for AutoFDO, having the correct uncompressed `vmlinux` with debug info is
crucial.

```bash
nix-shell -p autofdo
create_llvm_prof --binary=/run/current-system/kernel/vmlinux --profile=perf.data --format=extbinary --out=kernel.afdo
```

*Note: If `/run/current-system/kernel/vmlinux` is stripped or compressed (bzImage), you may need to
get the `vmlinux` from the build derivation of your current kernel.*

### 4. Optimized Build

Move the generated `kernel.afdo` to your NixOS configuration directory (e.g.,
`files/profiles/kernel.afdo`).

Update your host configuration:

```nix
boot.kernel.autofdo.enable = true;
boot.kernel.autofdo.profile = ./path/to/kernel.afdo; # e.g. ../../files/profiles/kernel.afdo
```

Rebuild your system:

```bash
sudo nixos-rebuild switch --flake .#telfir
```

The new kernel is now PGO-optimized for your workload.
