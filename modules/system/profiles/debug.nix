##
# Module: system/profiles/debug
# Purpose: Optional debug/profiling toggles related to recent kernel features
# - Memory allocation profiling (6.10+): CONFIG_MEM_ALLOC_PROFILING (+ boot param)
# - perf data-type profiling helpers (6.8+): install tools, optional kernel BTF
# - vDSO getrandom (6.11+): informational only
#
# Default: disabled (no changes unless explicitly enabled by the user).
{
  lib,
  pkgs,
  config,
  ...
}: let
  opts = import ../../../lib/opts.nix {inherit lib;};
  cfg = config.profiles.debug or {enable = false;};

  # Minimal helper to check kernel version strings like "6.11" etc.
  kver = config.boot.kernelPackages.kernel.version or "";
  haveAtLeast = v: (kver != "") && lib.versionAtLeast kver v;
in {
  options.profiles.debug = {
    enable = opts.mkEnableOption "Enable debug/profiling helpers (kernel memory allocation profiling, perf data-type tooling).";

    memAllocProfiling = {
      # Runtime activation via boot param (requires kernel built with CONFIG_MEM_ALLOC_PROFILING)
      enable = opts.mkBoolOpt {
        default = false;
        description = "Enable kernel memory allocation profiling at boot (sysctl.vm.mem_profiling=1[,compressed]).";
      };
      compressed = opts.mkBoolOpt {
        default = false;
        description = "Request compressed tag storage (adds ',compressed' to sysctl.vm.mem_profiling).";
      };

      # Build-time kernel config toggles for the feature (causes kernel rebuild when true)
      compileSupport = opts.mkBoolOpt {
        default = false;
        description = "Ensure CONFIG_MEM_ALLOC_PROFILING=y in the kernel (rebuilds the kernel).";
      };
      enabledByDefault = opts.mkBoolOpt {
        default = false;
        description = "Set CONFIG_MEM_ALLOC_PROFILING_ENABLED_BY_DEFAULT=y (profiling defaults to on unless overridden by boot param).";
      };
      debugChecks = opts.mkBoolOpt {
        default = false;
        description = "Enable CONFIG_MEM_ALLOC_PROFILING_DEBUG (warn about unaccounted allocations).";
      };
    };

    perfDataType = {
      enable = opts.mkBoolOpt {
        default = false;
        description = "Install perf + dwarves(pahole) to use perf data-type profiling and related tooling.";
      };
      enableKernelBtf = opts.mkBoolOpt {
        default = false;
        description = "Force CONFIG_DEBUG_INFO_BTF=y for better BPF/introspection (rebuilds the kernel).";
      };
      installTools = opts.mkBoolOpt {
        default = true;
        description = "Install perf and dwarves (pahole) into the system when perfDataType.enable is true.";
      };
    };

    # sched_ext: BPF-based extensible scheduler (6.12+)
    schedExt = {
      enable = opts.mkBoolOpt {
        default = false;
        description = "Enable kernel support for sched_ext (CONFIG_SCHED_CLASS_EXT) and install BPF tooling.";
      };
      installTools = opts.mkBoolOpt {
        default = true;
        description = "Install bpftools and clang for building/loading sched_ext examples.";
      };
      enableKernelBtf = opts.mkBoolOpt {
        default = false;
        description = "Force CONFIG_DEBUG_INFO_BTF=y to improve BPF/sched_ext introspection (rebuilds kernel).";
      };
    };
  };

  # Apply when the global toggle is on OR any sub-feature is explicitly enabled.
  config =
    lib.mkIf (
      (cfg.enable or false)
      || (cfg.memAllocProfiling.compileSupport or false)
      || (cfg.memAllocProfiling.enable or false)
      || (cfg.perfDataType.enable or false)
      || (cfg.perfDataType.enableKernelBtf or false)
      || (cfg.schedExt.enable or false)
      || (cfg.schedExt.enableKernelBtf or false)
    ) (
      lib.mkMerge [
        # Memory allocation profiling (6.10+)
        (lib.mkIf (cfg.memAllocProfiling.compileSupport or false) {
          boot.kernelPatches = [
            {
              name = "enable-mem-alloc-profiling";
              patch = null; # config-only change
              structuredExtraConfig = with lib.kernel;
                {
                  MEM_ALLOC_PROFILING = yes;
                }
                // (lib.optionalAttrs (cfg.memAllocProfiling.enabledByDefault or false) (
                  with lib.kernel; {MEM_ALLOC_PROFILING_ENABLED_BY_DEFAULT = yes;}
                ))
                // (lib.optionalAttrs (cfg.memAllocProfiling.debugChecks or false) (
                  with lib.kernel; {MEM_ALLOC_PROFILING_DEBUG = yes;}
                ));
            }
          ];
        })
        (lib.mkIf (cfg.memAllocProfiling.enable or false) {
          # Boot-param to set initial sysctl value
          boot.kernelParams = let
            base =
              if cfg.memAllocProfiling.enable
              then "sysctl.vm.mem_profiling=1"
              else "sysctl.vm.mem_profiling=never";
            suffix =
              if (cfg.memAllocProfiling.compressed or false)
              then ",compressed"
              else "";
          in [(base + suffix)];
        })

        # perf data-type tooling (6.8+)
        (lib.mkIf (cfg.perfDataType.enable or false) {
          environment.systemPackages = lib.mkIf (cfg.perfDataType.installTools or false) [
            pkgs.perf
            pkgs.dwarves # provides pahole for BTF/DWARF work
          ];
        })
        (lib.mkIf (cfg.perfDataType.enableKernelBtf or false) {
          # Force kernel to be built with BTF info
          boot.kernelPatches = [
            {
              name = "enable-kernel-btf";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                DEBUG_INFO_BTF = yes;
              };
            }
          ];
        })

        # sched_ext kernel support and tooling (6.12+)
        (lib.mkIf (cfg.schedExt.enable or false) {
          boot.kernelPatches =
            [
              {
                name = "enable-sched-ext";
                patch = null;
                structuredExtraConfig = with lib.kernel; {
                  SCHED_CLASS_EXT = yes;
                  BPF = yes;
                  BPF_SYSCALL = yes;
                  BPF_JIT = yes;
                  BPF_JIT_DEFAULT_ON = yes;
                };
              }
            ]
            ++ lib.optionals (cfg.schedExt.enableKernelBtf or false) [
              {
                name = "enable-kernel-btf-for-sched-ext";
                patch = null;
                structuredExtraConfig = with lib.kernel; {
                  DEBUG_INFO_BTF = yes;
                };
              }
            ];

          environment.systemPackages = lib.mkIf (cfg.schedExt.installTools or false) [
            pkgs.bpftools
            pkgs.clang
          ];
        })

        # Evaluation Noise Policy: avoid warnings during evaluation; document expectations in option descriptions.
      ]
    );
}
