{ inputs, ... }:
# ROCm-enabled PyTorch 2.12 (gfx1201) python environment for GPU fine-tuning.
# Self-contained: imports the flake's nixpkgs with allowBroken/allowUnfree (ROCm
# deps include a "broken" composable_kernel base) + doCheckByDefault=false (prunes
# scipy/matplotlib test deps). gfx targets restricted to gfx1201 (RX 9070 XT);
# doc/test deps pruned (rdc/rocdbgapi docs off, rccl without the rocprofiler profiler).
let
  nixpkgs = inputs.nixpkgs.outPath;
  libcpp15patch = ./boost-libcpp15.patch;
  pkgs = import nixpkgs {
    system = "x86_64-linux";
    config = {
      allowBroken = true;
      allowUnfree = true;
      doCheckByDefault = false;
    };
    overlays = [
      # boost.org serves a 302 redirect for this patch (hash mismatch); vendor it.
      (_final: prev: {
        boost179 = prev.boost179.overrideAttrs (old: {
          patches =
            builtins.filter (p: (builtins.match ".*libcpp15.*" (p.name or "")) == null) (old.patches or [ ])
            ++ [ libcpp15patch ];
        });
      })
    ];
  };
  rocm = pkgs.rocmPackages.overrideScope (
    _final: prev: {
      clr = prev.clr.overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          localGpuTargets = [ "gfx1201" ];
        };
      });
      rocdbgapi = prev.rocdbgapi.override { buildDocs = false; };
      rdc = prev.rdc.override { buildDocs = false; };
      rccl = prev.rccl.overrideAttrs (old: {
        # rocprofiler pulls openmpi -> rdma-core -> pandoc/GHC (hours of builds);
        # rccl only needs it for optional profiling support.
        buildInputs = builtins.filter (p: (builtins.match ".*rocprofiler-[0-9].*" (p.name or "")) == null) (
          old.buildInputs or [ ]
        );
      });
    }
  );
  torchRocm = pkgs.python3Packages.torch.override {
    rocmSupport = true;
    rocmPackages = rocm;
  };
in
# No `meta`: this is a Python *environment* (python3.withPackages), not a single
# package — the members carry their own meta, and withPackages does not accept
# one (audit 2026-09-15; the other packages under packages/ set meta normally).
pkgs.python3.withPackages (ps: [
  torchRocm
  ps.numpy
])
