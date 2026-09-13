{
  lib,
  buildGoModule,
  fetchFromGitHub,
  buildEnv,
  makeBinaryWrapper,
  stdenv,
  addDriverRunpath,

  cmake,
  gitMinimal,
  clblast,
  libdrm,
  rocmPackages,
  rocmGpuTargets ? rocmPackages.clr.localGpuTargets or (rocmPackages.clr.gpuTargets or [ ]),
  cudaPackages,
  cudaArches ? cudaPackages.flags.realArches or [ ],
  autoAddDriverRunpath,
  apple-sdk_15,
  vulkan-tools,
  vulkan-headers,
  vulkan-loader,
  spirv-headers,
  shaderc,
  ccache,

  versionCheckHook,
  writableTmpDirAsHomeHook,

  # passthru
  nixosTests,
  ollama,
  ollama-rocm,
  ollama-cuda,
  ollama-vulkan,

  config,
  # one of `[ null false "rocm" "cuda" "vulkan" ]`
  acceleration ? null,
}:

assert builtins.elem acceleration [
  null
  false
  "rocm"
  "cuda"
  "vulkan"
];

let
  validateFallback = lib.warnIf (config.rocmSupport && config.cudaSupport) (lib.concatStrings [
    "both `nixpkgs.config.rocmSupport` and `nixpkgs.config.cudaSupport` are enabled, "
    "but they are mutually exclusive; falling back to cpu"
  ]) (!(config.rocmSupport && config.cudaSupport));
  shouldEnable =
    mode: fallback: (acceleration == mode) || (fallback && acceleration == null && validateFallback);

  rocmRequested = shouldEnable "rocm" config.rocmSupport;
  cudaRequested = shouldEnable "cuda" config.cudaSupport;
  vulkanRequested = acceleration == "vulkan";

  enableRocm = rocmRequested && stdenv.hostPlatform.isLinux;
  enableCuda = cudaRequested && stdenv.hostPlatform.isLinux;
  enableVulkan = vulkanRequested && stdenv.hostPlatform.isLinux;

  rocmLibs = [
    rocmPackages.clr
    rocmPackages.hipblas-common
    rocmPackages.hipblas
    rocmPackages.rocblas
    rocmPackages.rocsolver
    rocmPackages.rocsparse
    rocmPackages.rocm-device-libs
    rocmPackages.rocm-smi
  ];
  rocmPath = buildEnv {
    name = "rocm-path";
    paths = rocmLibs;
  };

  cudaLibs = [
    cudaPackages.cuda_cudart
    cudaPackages.libcublas
    cudaPackages.cccl
  ];

  vulkanLibs = [
    vulkan-headers
    vulkan-loader
  ];

  # Extract the major version of CUDA. e.g. 11 12
  cudaMajorVersion = lib.versions.major cudaPackages.cuda_cudart.version;

  cudaToolkit = buildEnv {
    # ollama hardcodes the major version in the Makefile to support different variants.
    # - https://github.com/ollama/ollama/blob/v0.31.1/CMakePresets.json#L21-L47
    name = "cuda-merged-${cudaMajorVersion}";
    paths = map lib.getLib cudaLibs ++ [
      (lib.getOutput "static" cudaPackages.cuda_cudart)
      (lib.getBin (cudaPackages.cuda_nvcc.__spliced.buildHost or cudaPackages.cuda_nvcc))
    ];

    # cccl and cuda_cudart both have a LICENSE file in their output
    ignoreCollisions = true;
  };

  cudaPath = lib.removeSuffix "-${cudaMajorVersion}" cudaToolkit;

  # Since v0.30, llama.cpp is consumed via CMake FetchContent rather than
  # vendored in-tree. Pre-stage the pin (tracks upstream's
  # `LLAMA_CPP_VERSION` file) so the FetchContent step uses our copy
  # instead of trying to clone over the network in the sandbox.
  # Bumped from b10242 to match ollama v0.32.15's LLAMA_CPP_VERSION (needed
  # for the qwen3.8 renderer/engine).
  llamaCppVersion = "b10488";
  llamaCppSrc = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    tag = llamaCppVersion;
    hash = "sha256-5noPIcSD9Ki1D3J7b6JofeXiPO1RdL/Q8z+E0ZCwceY=";
  };

  wrapperOptions = [
    # ollama embeds llama-cpp binaries which actually run the ai models
    # these llama-cpp binaries are unaffected by the ollama binary's DT_RUNPATH
    # LD_LIBRARY_PATH is temporarily required to use the gpu
    # until these llama-cpp binaries can have their runpath patched
    "--suffix LD_LIBRARY_PATH : '${addDriverRunpath.driverLink}/lib'"
  ]
  ++ lib.optionals enableRocm [
    "--suffix LD_LIBRARY_PATH : '${rocmPath}/lib'"
    "--set-default HIP_PATH '${rocmPath}'"
  ]
  ++ lib.optionals enableCuda [
    "--suffix LD_LIBRARY_PATH : '${lib.makeLibraryPath (map lib.getLib cudaLibs)}'"
  ]
  ++ lib.optionals enableVulkan [
    "--suffix LD_LIBRARY_PATH : '${lib.makeLibraryPath (map lib.getLib vulkanLibs)}'"
    "--set-default OLLAMA_VULKAN '1'"
  ];
  wrapperArgs = builtins.concatStringsSep " " wrapperOptions;

  goBuild =
    if enableCuda then
      buildGoModule.override { stdenv = cudaPackages.backendStdenv; }
    else if enableRocm then
      buildGoModule.override { inherit (rocmPackages) stdenv; }
    else if enableVulkan then
      buildGoModule.override { inherit (vulkan-tools) stdenv; }
    else
      buildGoModule;
  inherit (lib) licenses platforms maintainers;
in
goBuild (finalAttrs: {
  pname = "ollama";
  version = "0.32.15";

  src = fetchFromGitHub {
    owner = "ollama";
    repo = "ollama";
    tag = "v${finalAttrs.version}";
    hash = "sha256-BpN3y1unf6Yd1RBura2S4O5jLSkImzi1Guo6GWbNZI8=";
  };

  # v0.32.15's Go module set is identical to 0.32.7's (verified via build).
  vendorHash = "sha256-HMwoaFBMbpoy8f0I+O+i7kIa9BslLu3FcVWeaIOkpvs=";
  proxyVendor = true;

  env =
    lib.optionalAttrs enableRocm {
      ROCM_PATH = rocmPath;
      CLBlast_DIR = "${clblast}/lib/cmake/CLBlast";
      HIP_PATH = rocmPath;
      CFLAGS = "-Wno-c++17-extensions -I${rocmPath}/include";
      CXXFLAGS = "-Wno-c++17-extensions -I${rocmPath}/include";
    }
    // lib.optionalAttrs enableCuda { CUDA_PATH = cudaPath; }
    // lib.optionalAttrs enableVulkan { VULKAN_SDK = shaderc.bin; };

  nativeBuildInputs = [
    cmake
    gitMinimal
  ]
  ++ lib.optionals enableRocm (
    rocmLibs
    ++ [
      rocmPackages.llvm.bintools
    ]
  )
  ++ lib.optionals enableCuda [ cudaPackages.cuda_nvcc ]
  ++ lib.optionals (enableRocm || enableCuda) [
    makeBinaryWrapper
    autoAddDriverRunpath
  ]
  ++ lib.optionals enableVulkan [
    ccache
    # ggml-vulkan/CMakeLists.txt does `find_package(SPIRV-Headers REQUIRED)`
    # at configure time (it builds shader code into the vulkan backend).
    # Header-only — nativeBuildInputs is the right slot.
    spirv-headers
  ];

  buildInputs =
    lib.optionals enableRocm (rocmLibs ++ [ libdrm ])
    ++ lib.optionals enableCuda cudaLibs
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ apple-sdk_15 ]
    ++ lib.optionals enableVulkan vulkanLibs;

  # replace inaccurate version number with actual release version
  postPatch =
    builtins.replaceStrings [ "@VERSION@" "@LLAMACPPSRC@" ] [ "${finalAttrs.version}" "${llamaCppSrc}" ]
      (builtins.readFile ./post-patch.sh.in);

  overrideModAttrs = _: _: {
    # don't run llama.cpp build in the module fetch phase
    preBuild = "";
  };

  preBuild =
    let
      removeSMPrefix =
        str:
        let
          matched = builtins.match "sm_(.*)" str;
        in
        if matched == null then str else builtins.head matched;

      cudaArchitectures = builtins.concatStringsSep ";" (map removeSMPrefix cudaArches);
      rocmTargets = builtins.concatStringsSep ";" rocmGpuTargets;

      # Since 0.30, Ollama splits the llama.cpp build into per-accelerator
      # "runners" gated by OLLAMA_LLAMA_BACKENDS. Without setting it the
      # build silently produces only the CPU runner — ollama-cuda would
      # ship without `libggml-cuda.so` and fall back to CPU at runtime.
      # The accepted values map to cmake/local.cmake's elseif chain
      # (cuda_v12 / cuda_v13 / rocm_v7_1 / rocm_v7_2 / vulkan / cuda_jetpack*).
      rocmMajorVersion = lib.versions.major rocmPackages.clr.version;
      rocmMinorVersion = lib.versions.minor rocmPackages.clr.version;
      llamaBackend =
        if enableCuda then
          "cuda_v${cudaMajorVersion}"
        else if enableRocm then
          "rocm_v${rocmMajorVersion}_${rocmMinorVersion}"
        else if enableVulkan then
          "vulkan"
        else
          "";

      cmakeFlagsCudaArchitectures = lib.optionalString enableCuda "-DCMAKE_CUDA_ARCHITECTURES='${cudaArchitectures}'";
      cmakeFlagsRocmTargets = lib.optionalString enableRocm "-DAMDGPU_TARGETS='${rocmTargets}'";
      cmakeFlagsBackend = lib.optionalString (
        llamaBackend != ""
      ) "-DOLLAMA_LLAMA_BACKENDS=${llamaBackend}";

    in
    builtins.replaceStrings
      [
        "@NIX_CFLAGS_COMPILE@"
        "@CMAKEFLAGSCUDAARCHITECTURES@"
        "@CMAKEFLAGSROCMTARGETS@"
        "@CMAKEFLAGSBACKEND@"
      ]
      [
        (lib.optionalString enableVulkan (
          builtins.replaceStrings [ "@HEADERS@" "@HEADERS_V2@" ] [ "${spirv-headers}" "${spirv-headers}" ] (
            builtins.readFile ./vulkan-env.sh.in
          )
        ))
        "${cmakeFlagsCudaArchitectures}"
        "${cmakeFlagsRocmTargets}"
        "${cmakeFlagsBackend}"
      ]
      (builtins.readFile ./pre-build.sh.in);

  # The llama.cpp sub-build is driven by ExternalProject_Add and does
  # not inherit the parent's CMAKE_SKIP_BUILD_RPATH setting, so its
  # `.so` payloads end up with build-dir entries in RPATH. Drop them
  # before the forbidden-references check. $ORIGIN is preserved
  # unconditionally; only absolute /nix/store entries are kept.
  # ELF-only (patchelf doesn't know Mach-O); darwin builds Mach-O dylibs
  # that don't carry the build-dir RPATH problem in the first place.
  preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    find $out/lib/ollama -type f \( -name '*.so' -o -name '*.so.*' \) \
      -exec patchelf --shrink-rpath --allowed-rpath-prefixes /nix/store {} +
  '';

  # ollama looks for acceleration libs in ../lib/ollama/ (now also for CPU-only with arch specific optimizations)
  # https://github.com/ollama/ollama/blob/v0.31.1/docs/development.md#library-detection
  postInstall = ''
    mkdir -p $out/lib
    cp -r build/lib/ollama $out/lib/
  '';

  postFixup =
    # expose runtime libraries necessary to use the gpu
    lib.optionalString (enableRocm || enableCuda) ''
      wrapProgram "$out/bin/ollama" ${wrapperArgs}
    '';

  ldflags = [
    "-X=github.com/ollama/ollama/version.Version=${finalAttrs.version}"
    "-X=github.com/ollama/ollama/server.mode=release"
  ];

  __darwinAllowLocalNetworking = true;

  # required for github.com/ollama/ollama/detect's tests
  sandboxProfile = lib.optionalString stdenv.hostPlatform.isDarwin ''
    (allow file-read* (subpath "/System/Library/Extensions"))
    (allow iokit-open (iokit-user-client-class "AGXDeviceUserClient"))
  '';

  checkFlags =
    let
      # Skip tests that require network access
      skippedTests = [
        "TestPushHandler/unauthorized_push" # Writes to $HOME, see https://github.com/ollama/ollama/pull/12307#pullrequestreview-3249128660
        "TestPiRun_InstallAndWebSearchLifecycle" # Requires network access to install npm packages
      ];
    in
    [ "-skip=^${builtins.concatStringsSep "$|^" skippedTests}$" ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  versionCheckKeepEnvironment = "HOME";

  passthru = {
    inherit llamaCppSrc llamaCppVersion;
    tests = {
      inherit ollama;
    }
    // lib.optionalAttrs stdenv.hostPlatform.isLinux {
      inherit ollama-rocm ollama-cuda ollama-vulkan;
      service = nixosTests.ollama;
      service-cuda = nixosTests.ollama-cuda;
      service-rocm = nixosTests.ollama-rocm;
      service-vulkan = nixosTests.ollama-vulkan;
    };
  }
  // lib.optionalAttrs (!enableRocm && !enableCuda && !enableVulkan) { updateScript = ./update.sh; };

  meta = {
    description =
      "Get up and running with large language models locally"
      + lib.optionalString rocmRequested ", using ROCm for AMD GPU acceleration"
      + lib.optionalString cudaRequested ", using CUDA for NVIDIA GPU acceleration"
      + lib.optionalString vulkanRequested ", using Vulkan for generic GPU acceleration";
    homepage = "https://github.com/ollama/ollama";
    changelog = "https://github.com/ollama/ollama/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    platforms =
      if (rocmRequested || cudaRequested || vulkanRequested) then platforms.linux else platforms.unix;
    mainProgram = "ollama";
    maintainers = with maintainers; [
      prusnak
    ];
    # install TARGETS RUNTIME_DEPENDENCIES is not supported when cross-compiling.
    broken = stdenv.buildPlatform != stdenv.hostPlatform;
  };
})
