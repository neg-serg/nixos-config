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

  meta = with lib; {
    description = "Vulkan-accelerated wallpaper daemon for Wayland compositors";
    homepage = "https://github.com/neg-serg/wl";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    mainProgram = "wl";
  };
}
