{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  addDriverRunpath,
  vulkan-loader,
}:

# audio.cpp is a ggml-based runtime for audio models (TTS, ASR, music
# understanding, separation, ...); this is the prebuilt Ubuntu x64 Vulkan
# release, which is the only way to run its model set on this host without a
# CUDA toolchain.  The tarball ships the CLI, the server and the libggml
# backends (including libggml-vulkan.so) flat next to each other, and libggml
# dlopens libvulkan.so.1 at run time — so the wrapper carries the loader, the
# driver runpath (mesa RADV provides the ICD on NixOS) and the bundled libs.
#
# Models are GGUF files fetched separately; see scripts/dev/audio-cpp-models.sh
# and docs/howto/local-music-ai.md.
stdenv.mkDerivation (finalAttrs: {
  pname = "audio-cpp";
  version = "0.9.2-drama3-base-small";

  src = fetchurl {
    name = "audio-cpp-${finalAttrs.version}-vulkan.tar.gz";
    url = "https://github.com/0xShug0/audio.cpp/releases/download/v${finalAttrs.version}/audio-v${finalAttrs.version}-bin-ubuntu-x64-vulkan-portable.tar.gz";
    hash = "sha256-39CtgygpIQ6xOgN3m92Q8+bmj2jt92K/JbORUGe+63M=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    (lib.getLib stdenv.cc.cc) # libstdc++/libgcc_s for the CLI
    vulkan-loader
  ];

  strictDeps = true;
  # The tarball unpacks its binaries and libggml backends flat, with no top
  # directory, which the default unpacker refuses.
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/audio-cpp $out/bin
    cp -r ./. $out/libexec/audio-cpp/

    # Every entry point needs the same library path: the bundled ggml backends
    # live beside the binary, and vulkan-loader plus the driver link are not
    # discoverable from an unpacked tarball.
    for tool in audiocpp_cli audiocpp_server audiocpp_gguf; do
      makeWrapper $out/libexec/audio-cpp/$tool $out/bin/$tool \
        --prefix LD_LIBRARY_PATH : "$out/libexec/audio-cpp:${
          lib.makeLibraryPath [
            addDriverRunpath.driverLink
            vulkan-loader
          ]
        }"
    done

    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "ggml-based runtime for local audio models (CLI, server, GGUF tooling)";
    homepage = "https://github.com/0xShug0/audio.cpp";
    license = lib.licenses.unfree; # the runtime itself; models carry their own terms
    mainProgram = "audiocpp_cli";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
