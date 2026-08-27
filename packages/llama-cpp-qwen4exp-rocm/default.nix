{
  lib,
  fetchFromGitHub,
  llama-cpp,
  llama-cpp-rocm,
  rocmPackages,
}:
let
  # Same llama.cpp PR #27742 head as the Vulkan build — but with the ROCm (HIP)
  # backend: on this host (RX 9070 XT / gfx1201) the Vulkan/RADV llama.cpp path
  # is pathologically slow (~0.2 tok/s even for VRAM-resident models), while
  # ROCm works (ollama: 7.7 tok/s on 27B). This build gives llama.cpp the
  # working compute path for qwen4exp (Qwen3.8-Flash-Next).
  rev = "0b19188e935480369f3b006e0cf17576dce066a3";
in
(llama-cpp-rocm.override {
  # Build the ROCm dependency closure for this host's GPU only (gfx1201).
  # nixpkgs' base rocmPackages scope targets every GCN/RDNA arch, so Tensile
  # would generate assembly kernels for all of them (hours of extra build).
  # callPkg resolves this package's deps from the un-overlaid pkgs, so the
  # global `rocmPackages = ...gfx1201` override does not reach it — apply the
  # same per-arch scope here (llama-cpp-rocm adds rocmSupport itself).
  llama-cpp = llama-cpp.override {
    rocmPackages = rocmPackages.gfx1201;
  };
}).overrideAttrs (old: {
  pname = "llama-cpp-qwen4exp-rocm";
  # Numeric: nixpkgs' llama-cpp injects version into LLAMA_BUILD_NUMBER (C++ int).
  version = "10656";

  src = fetchFromGitHub {
    owner = "unslothai";
    repo = "llama.cpp";
    inherit rev;
    sha256 = "sha256-xcEfwle+bUHkYuZzfqVqXyi+ue3cvWsiuEbaaBDb0z4=";
  };

  meta = old.meta // {
    description = "llama.cpp with experimental Qwen3.8-Flash-Next (qwen4exp) support — PR #27742, ROCm (HIP) build";
    longDescription = ''
      Unmerged llama.cpp PR #27742 (unslothai/llama.cpp, branch
      qwen4exp/qwen3.8-flash-next) built against the ROCm/HIP backend for the
      RX 9070 XT (gfx1201). ROCm deps (hipblaslt/rocblas/...) scoped to gfx1201
      only, so Tensile skips the other 9 GCN/RDNA archs. Serves
      Qwen3.8-Flash-Next GGUFs; on this host ROCm compute is fast while the
      Vulkan path is not.
    '';
    homepage = "https://github.com/ggml-org/llama.cpp/pull/27742";
    license = lib.licenses.mit;
  };
})
