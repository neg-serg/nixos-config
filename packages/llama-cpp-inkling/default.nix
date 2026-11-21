{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  shaderc,
  spirv-headers,
  vulkan-headers,
  vulkan-loader,
  openssl,
}:

# llama.cpp at the change that makes Inkling-2-Mini decode correctly, built as a
# second binary beside the nixpkgs `llama-cpp-vulkan`. Two upstream changes are
# needed and neither is in 0.7.0 (nixpkgs, build 11669):
#
#   - #32694, the `inkling2_loop` architecture itself (merged 2026-11-20);
#   - #32704, which re-shares the loop slots after the scale pass. Still open,
#     and without it the second and third passes through the looped layers lose
#     their per-expert NVFP4 scales: perplexity lands near 130 instead of 7.65,
#     i.e. llama-server answers fluently and wrongly, which is worse than
#     refusing the file.
#
# The rev is the PR's *merge* ref (master + the PR) rather than its head: the
# head is branched from a tree that predates the `app/` move, and nixpkgs'
# packaging of 0.7.0 (npm root at `tools/ui`) does not fit it. Only the Inkling
# tiers point at this derivation; every other tier keeps the stable
# `llama-cpp-vulkan`, so a PR-only regression cannot reach the rest of the
# stack. Delete this package once nixpkgs ships a llama-cpp at or after the
# #32704 merge.
stdenv.mkDerivation {
  pname = "llama-cpp-inkling";
  version = "1.0.0-pr32704";

  src = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = "703a22ca1be45f1bccece77d756791738ac7d692";
    hash = "sha256-VoBt+gGvfbNWVK9su2ErnaiNVPMlq7aRNUqUQbn1dx4=";
  };

  # Upstream builds the server's web UI with npm from `tools/ui`, which this
  # tree no longer has (the wasm `app/` is unrelated and off). Nothing here
  # reads the UI: llama-swap speaks the OpenAI API.
  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    shaderc # glslc compiles the Vulkan shaders at build time
  ];

  buildInputs = [
    openssl
    spirv-headers
    vulkan-headers
    vulkan-loader
  ];

  cmakeFlags = [
    (lib.cmakeBool "GGML_NATIVE" false) # -march=native would bind the binary to this CPU
    (lib.cmakeBool "GGML_VULKAN" true)
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeBool "LLAMA_BUILD_SERVER" true)
    (lib.cmakeBool "LLAMA_BUILD_TOOLS" true) # llama-bench, mtmd
    (lib.cmakeBool "LLAMA_BUILD_EXAMPLES" false)
    (lib.cmakeBool "LLAMA_BUILD_TESTS" false)
    (lib.cmakeBool "LLAMA_BUILD_HTML" false)
    (lib.cmakeBool "LLAMA_BUILD_IS_DEV" false)
    (lib.cmakeBool "LLAMA_OPENSSL" true)
    (lib.cmakeFeature "LLAMA_BUILD_NUMBER" "32704")
    (lib.cmakeFeature "LLAMA_BUILD_COMMIT" "703a22ca")
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "llama.cpp with the Inkling-2-Mini looped-layer fix (Vulkan)";
    homepage = "https://github.com/ggml-org/llama.cpp/pull/32704";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    maintainers = [ ];
    mainProgram = "llama-server";
  };
}
