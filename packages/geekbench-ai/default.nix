{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  addDriverRunpath,
  ocl-icd,
  vulkan-loader,
}:

# Geekbench AI ships its binaries under the internal codename `banff`
# (banff / banff_avx2 / banff_x86_64); the workload data sits next to them
# (banff-workload.plar is ~1 GB — the bulk of the download).
stdenv.mkDerivation (finalAttrs: {
  pname = "geekbench-ai";
  version = "1.8.0";

  src = fetchurl {
    name = "GeekbenchAI-${finalAttrs.version}-Linux.tar.gz";
    url = "https://cdn.geekbench.com/GeekbenchAI-${finalAttrs.version}-Linux.tar.gz";
    hash = "sha256-l3fJtbgs4laM29Yoe4femG9J/7TN3hIWl+ST7COJEdQ=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    (lib.getLib stdenv.cc.cc)
    ocl-icd
    vulkan-loader
  ];

  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/geekbench-ai $out/bin
    cp -r ./. $out/libexec/geekbench-ai/

    # The `banff` launcher picks the avx2/x86_64 variant itself and the
    # children inherit the environment, so wrapping the launcher is enough.
    makeWrapper $out/libexec/geekbench-ai/banff $out/bin/geekbench-ai \
      --prefix LD_LIBRARY_PATH : "$out/libexec/geekbench-ai:${
        lib.makeLibraryPath [
          addDriverRunpath.driverLink
          ocl-icd
          vulkan-loader
        ]
      }"

    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "On-device AI inference benchmark (Geekbench AI, CPU/GPU)";
    homepage = "https://www.geekbench.com/ai/";
    license = lib.licenses.unfree;
    mainProgram = "geekbench-ai";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
