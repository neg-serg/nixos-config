{
  lib,
  rustPlatform,
  shaderc,
  pkg-config,
  makeWrapper,
  wayland,
  vulkan-loader,
  libxkbcommon,
  inputs,
}:
rustPlatform.buildRustPackage rec {
  pname = "wl";
  version = "0.1.0";

  src = inputs.wl;

  cargoLock.lockFile = "${inputs.wl}/Cargo.lock";

  # Silence the "recovering lost surface" warning on monitor restore (DPMS
  # off→on): the recovery itself still runs, the message is just demoted to
  # debug so it only shows with RUST_LOG=debug.
  #
  # vulkan-device-lost.patch: a transition left running while a plain `wl img`
  # / `wl restore` (TransitionType::None) replaces the wallpaper kept sampling
  # the destroyed old texture (radv GPUVM fault, CLIENT_ID TCP → device lost).
  patches = [
    ./silence-surface-recovery-log.patch
    ./vulkan-device-lost.patch
  ];

  nativeBuildInputs = [
    makeWrapper
    shaderc # for glslc (Vulkan shader compilation)
    pkg-config
  ];

  buildInputs = [
    wayland
    vulkan-loader
    libxkbcommon
  ];

  postFixup = ''
    wrapProgram "$out/bin/wl" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ vulkan-loader ]}
    wrapProgram "$out/bin/wl-daemon" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ vulkan-loader ]}
  '';

  meta = lib.mkMeta {
    description = "Vulkan-accelerated wallpaper daemon for Wayland compositors";
    homepage = "https://github.com/neg-serg/wl";
    license = lib.licenses.gpl3Only;
    mainProgram = "wl";
  };
}
