{ inputs, paths, ... }:
# ROCm-enabled vLLM (gfx1201) python environment — the OpenAI-compatible LLM
# server for the RX 9070 XT (Navi 48, RDNA4).
#
# Built from the *same* pinned nixpkgs as packages/torch-rocm (torch 2.12.0):
# the main pin's torch 2.13.0 wants aotriton 0.12b while its rocmPackages ship
# 0.11.1b, so a HIP torch from the main pin does not build. Everything here is
# arranged so the already-built ROCm torch/rocmPackages closure is reused
# instead of rebuilt:
#   - `clr.localGpuTargets = [ "gfx1201" ]` keeps rocmPackages from compiling
#     kernels for every GPU family (the default list spans gfx900…gfx1201);
#   - every package that takes its own `rocmPackages` argument (vllm itself,
#     amd-aiter) is handed that restricted scope, otherwise it pulls the
#     full-target miopen/composable_kernel and starts a multi-hour rebuild;
#   - the vendored boost179 patch is the same one torch-rocm applies, so the
#     ROCm tree (and therefore torch) hashes identically and is substituted
#     from the store instead of rebuilt.
#
# vLLM's own C++/HIP kernels *are* compiled here (tens of minutes): nixpkgs has
# no ROCm binary cache for them.
let
  # Pinned rev: see packages/torch-rocm/default.nix (torch 2.12.0 + vllm 0.24.0).
  nixpkgs = inputs.nixpkgs-torch.outPath;
  # boost.org serves a 302 redirect for the 1.79 libc++15 patch (hash mismatch);
  # the copy vendored for torch-rocm is reused verbatim — same file, same store
  # path, so the ROCm derivations stay identical.
  libcpp15patch = paths.path "packages/torch-rocm/boost-libcpp15.patch";

  base = import nixpkgs {
    system = "x86_64-linux";
    config = {
      allowBroken = true; # ROCm deps include a "broken" composable_kernel base
      allowUnfree = true;
      doCheckByDefault = false; # prunes scipy/matplotlib test deps
    };
    overlays = [
      (_final: prev: {
        boost179 = prev.boost179.overrideAttrs (old: {
          patches =
            builtins.filter (p: (builtins.match ".*libcpp15.*" (p.name or "")) == null) (old.patches or [ ])
            ++ [ libcpp15patch ];
        });
      })
    ];
  };

  # ROCm stack restricted to the RX 9070 XT's ISA (see the header).
  rocm = base.rocmPackages.overrideScope (
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

  py = base.python314.override {
    packageOverrides = self: super: {
      # torch pulls the whole ROCm stack; override it in the scope so every
      # dependent (torchvision, torchaudio, bitsandbytes, vllm, …) agrees on it.
      torch = super.torch.override {
        rocmSupport = true;
        rocmPackages = rocm;
      };
      torchvision = super.torchvision.override { torch = self.torch; };
      torchaudio = super.torchaudio.override { torch = self.torch; };
      xformers = super.xformers.override { torch = self.torch; };
      # vllm/amd-aiter default to `pkgs.rocmPackages` (every GPU family);
      # point them at the gfx1201-only scope.
      vllm = super.vllm.override { rocmPackages = rocm; };
      amd-aiter = super.amd-aiter.override { rocmPackages = rocm; };
      # outlines lists tensorflow for its tests only, and nixpkgs has no
      # tensorflow-bin for python 3.14 — dropping it keeps the eval clean.
      tensorflow = null;
      # outlines pins doCheck = true, and its test_cache suite trips python
      # 3.14's DeprecationWarning-as-error on asyncio.iscoroutinefunction
      # (5 failed). Only the tests are broken; vllm imports it for structured
      # output, so skip them.
      outlines = super.outlines.overridePythonAttrs (_old: {
        doCheck = false;
      });
    };
  };
in
# No `meta`: this is a Python *environment* (python3.withPackages), not a single
# package — the members carry their own meta, and withPackages does not accept
# one (same note as packages/torch-rocm).
py.withPackages (ps: [ ps.vllm ])
