# Kernel AutoFDO Optimization Guide

This guide describes how to optimize the Linux kernel using AutoFDO (Auto-Feedback-Directed
Optimization). This technique allows building a kernel optimized for your specific workload using
production-collected profiles.

> **Status note (this host):** the `boot.kernel.autofdo` NixOS module
> (`modules/system/boot/autofdo.nix`) exists but is **not yet functional**. Odin builds its kernel
> through `modules/system/kernel/localmodconfig.nix`, whose
> `boot.kernelPackages = lib.mkOverride 40 …` outranks the module's `lib.mkForce` (priority 50), so
> enabling `boot.kernel.autofdo.enable` does **not** currently switch the kernel to Clang — its
> `AUTOFDO_CLANG y` patch also lands on a GCC build, where Kconfig drops it. The steps below describe
> the target workflow; before the profile takes effect the module must be wired into the
> localmodconfig build (build the minimized kernel with `clang` + `AUTOFDO_CLANG` +
> `CLANG_AUTOFDO_PROFILE`).

## Prerequisites

1. **Clang / LLVM**: AutoFDO for the kernel requires building with Clang (LLVM 17+). Profile
   generation uses `llvm-profgen`, which needs LLVM 19+. The pinned nixpkgs has `clang`/`llvm`
   21.1.8.
1. **PMU / LBR support**: x86_64 needs LBR; AMD needs Zen3 `brs` or Zen4+ `amd_lbr_v2`. This host
   (Ryzen 9 9950X3D, Zen 5) exposes `amd_lbr_v2`.
1. **Root for profiling**: kernel-space sampling requires root / `CAP_PERFMON`
   (`kernel.perf_event_paranoid=2` by default blocks non-root kernel profiling).
1. **A representative workload**: the profile only helps workloads that behave like the recorded
   one. AutoFDO is most beneficial for front-end-stall-bound workloads (compilation, JIT, databases),
   not I/O- or memory-bound ones.

## Workflow

### 1. Preparation (Instrumented Build)

Build the kernel with AutoFDO enabled but **without** a profile, so the build flags match the future
profile. In your host configuration (e.g. `hosts/odin/hardware.nix`):

```nix
boot.kernel.autofdo.enable = true;
# boot.kernel.autofdo.profile = null; # ensure this is null for the instrumented build
```

Apply the configuration and reboot into the new kernel. (See the status note above — this step only
produces a Clang kernel once the module is wired into localmodconfig.)

### 2. Profiling (Data Collection)

Record the representative workload with `perf`. The `-c` (sample period) should be a prime number
(e.g. `500009`) to avoid lockstep sampling bias.

#### AMD (this host: Zen 5, `amd_lbr_v2`)

```bash
# cpu/event=0xc4 = "Retired Taken Branch Instructions" on Zen 4/5.
# No libpfm/--pfm-events needed (odin's perf has no libpfm).
sudo perf record -b -e cpu/event=0xc4/k -a -N -c 500009 -o perf.data -- <workload>
```

Check support first: `grep -m1 amd_lbr_v2 /proc/cpuinfo` (or `brs` for Zen 3).

#### Intel (reference)

```bash
sudo perf record -b -e BR_INST_RETIRED.NEAR_TAKEN:k -a -N -c 500009 -o perf.data -- <workload>
```

### 3. Profile Generation

Convert `perf.data` into an LLVM extbinary AutoFDO profile with `llvm-profgen` (from `llvm`).
`create_llvm_prof` from the `autofdo` package is **not** available in nixpkgs.

You need the uncompressed `vmlinux` **with debug info** that matches the running Clang-built kernel.
On NixOS it is **not** at `/run/current-system/kernel/vmlinux` (that is `bzImage`); it lives in the
kernel package's `dev` output in the store:

```bash
nix build .#nixosConfigurations.odin.config.boot.kernelPackages.kernel.dev \
  --print-out-paths --no-link --option substitute false
# example output: /nix/store/<hash>-linux-6.18.40-dev
```

```bash
VMLINUX=/nix/store/<hash>-linux-6.18.40-dev/vmlinux
nix shell nixpkgs#llvm --inputs-from . --command \
  llvm-profgen --kernel --binary="$VMLINUX" --perfdata=perf.data -o kernel.afdo
```

Merge multiple runs into one profile with `llvm-profdata`:

```bash
nix shell nixpkgs#llvm --inputs-from . --command \
  llvm-profdata merge -o kernel.afdo run1.afdo run2.afdo
```

### 4. Optimized Build

Move `kernel.afdo` into the repo (e.g. `files/profiles/kernel.afdo`) and point the module at it:

```nix
boot.kernel.autofdo.enable = true;
boot.kernel.autofdo.profile = ../../files/profiles/kernel.afdo;
```

Rebuild and reboot:

```bash
sudo nixos-rebuild switch --flake .#odin --option substitute false
```

The new kernel is PGO-optimized for the recorded workload.
