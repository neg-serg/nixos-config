{
  lib,
  stdenv,
  glibc,
  libGL,
  vulkan-loader,
  makeWrapper,
  patchelf,
  qt6,
}:
stdenv.mkDerivation rec {
  pname = "lsfg-vk";
  version = "2.0.0-rc1";

  # Official prebuilt release from builds.lsfg-vk.dev (2026-08-27). Vendored:
  # builds.lsfg-vk.dev and git.lsfg-vk.dev are unreachable from this region
  # (direct git pack download hangs, cgit snapshots disabled), same pattern as
  # mprime below. License CC BY-NC-ND 4.0 — binaries shipped unmodified;
  # only the ELF interpreter/rpath are rewritten for the Nix store.
  src = ./../../files/sources/lsfg-vk-2.0.0-rc1.tar;

  nativeBuildInputs = [
    patchelf
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib # libstdc++
    glibc
  ];

  # The tarball is a plain tar despite the .tar.xz name; don't let fixup
  # re-strip/re-patchelf the binaries we already fixed in postInstall.
  dontFixup = true;

  unpackPhase = ''
    runHook preUnpack
    tar -xf "$src"
    runHook postUnpack
  '';

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/lsfg-vk-cli "$out/bin/lsfg-vk-cli"
    install -Dm755 bin/lsfg-vk-ui "$out/libexec/lsfg-vk-ui"
    install -Dm644 lib/liblsfg-vk-layer.so "$out/lib/liblsfg-vk-layer.so"
    mkdir -p "$out/share/vulkan/implicit_layer.d" "$out/share/applications" "$out/share/icons"
    # 64-bit manifest only (the .x86 32-bit variant has no NixOS multilib deps)
    cp share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json "$out/share/vulkan/implicit_layer.d/"
    cp -r share/applications/. "$out/share/applications/"
    cp -r share/icons/. "$out/share/icons/"
    runHook postInstall
  '';

  postInstall =
    builtins.replaceStrings
      [ "@RUNTIME@" "@QTDECLARATIVE@" "@QTBASE@" "@QTDECLARATIVE_V2@" "@QTBASE_V2@" ]
      [
        (lib.makeLibraryPath [
          stdenv.cc.cc.lib
          glibc
          vulkan-loader # libvulkan.so.1 — CLI/layer dlopen it at runtime
        ])
        (lib.makeLibraryPath [
          stdenv.cc.cc.lib
          glibc
          libGL
          qt6.qtbase
          qt6.qtdeclarative
        ])
        "${qt6.qtbase}"
        "${qt6.qtdeclarative}"
        "${qt6.qtbase}"
      ]
      (builtins.readFile ./post-install.sh);

  meta = lib.mkMeta {
    description = "Lossless Scaling Frame Generation on Linux — Vulkan frame-gen layer (requires owning Lossless Scaling on Steam, lsfg-vk branch)";
    homepage = "https://lsfg-vk.dev";
    # CC BY-NC-ND 4.0 (non-free): no commercial use, no derivatives.
    license = lib.licenses.cc-by-nc-nd-40;
    mainProgram = "lsfg-vk-cli";
  };
}
