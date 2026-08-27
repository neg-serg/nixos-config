{
  lib,
  fetchFromGitHub,
  llama-cpp-vulkan,
}:
let
  # llama.cpp PR #27742 head (unslothai fork, branch qwen4exp/qwen3.8-flash-next).
  # Experimental Qwen3.8-Flash-Next (qwen4exp arch) support — not merged upstream.
  rev = "0b19188e935480369f3b006e0cf17576dce066a3";
in
llama-cpp-vulkan.overrideAttrs (old: {
  pname = "llama-cpp-qwen4exp";
  # Must stay numeric: nixpkgs' llama-cpp injects version into
  # LLAMA_BUILD_NUMBER (C++ int literal) via build-info.cpp.in.
  # 10656 ~= PR head era build number (cosmetic; shown by --version).
  version = "10656";

  src = fetchFromGitHub {
    owner = "unslothai";
    repo = "llama.cpp";
    inherit rev;
    sha256 = "sha256-xcEfwle+bUHkYuZzfqVqXyi+ue3cvWsiuEbaaBDb0z4=";
  };

  # NOTE: the graph_max_nodes patch from the 16 GB recipe is no longer needed —
  # the PR head already lists LLM_ARCH_QWEN4EXP in graph_max_nodes (force-pushed).

  meta = old.meta // {
    description = "llama.cpp with experimental Qwen3.8-Flash-Next (qwen4exp) support — PR #27742, Vulkan build";
    longDescription = ''
      Unmerged llama.cpp PR #27742 (unslothai/llama.cpp, branch
      qwen4exp/qwen3.8-flash-next) plus the graph_max_nodes patch from the
      16 GB VRAM recipe. Serves UD-Q4_K_XL GGUFs of Qwen3.8-Flash-Next via the
      Vulkan (RADV) backend on the RX 9070 XT (gfx1201).
    '';
    homepage = "https://github.com/ggml-org/llama.cpp/pull/27742";
    license = lib.licenses.mit;
  };
})
