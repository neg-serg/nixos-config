{
  lib,
  rustPlatform,
  shaderc,
  pkg-config,
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
    shaderc # for glslc (Vulkan shader compilation)
    pkg-config
  ];

  buildInputs = [
    wayland
    vulkan-loader
    libxkbcommon
  ];

  meta = with lib; {
    description = "Vulkan-accelerated wallpaper daemon for Wayland compositors";
    homepage = "https://github.com/neg-serg/wl";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    mainProgram = "wl";
  };
}
