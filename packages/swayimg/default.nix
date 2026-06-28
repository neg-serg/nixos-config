{
  lib,
  stdenv,
  fetchurl,
  meson,
  ninja,
  pkg-config,
  wayland-scanner,
  wayland,
  wayland-protocols,
  libxkbcommon,
  fontconfig,
  freetype,
  luajit,
  giflib,
  libheif,
  libjpeg,
  libwebp,
  libtiff,
  librsvg,
  libpng,
  libjxl,
  exiv2,
  libavif,
  libsixel,
  libraw,
  libdrm,
  openexr,
  bash-completion,
  vulkan-headers,
  vulkan-loader,
  shaderc,
  xxd,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "swayimg";
  version = "0-unstable-fork";

  src = fetchurl {
    url = "https://github.com/neg-serg/swayimg/archive/refs/heads/master.tar.gz";
    hash = "sha256-1gioADzXI70kUq8u98Ajvp65SnqIoKVAHy3fJhuf8FQ=";
  };

  strictDeps = true;

  mesonFlags = [
    "-Dexr=disabled" # requires OpenEXR >=3.4, nixpkgs has 3.3.8
  ];

  depsBuildBuild = [
    pkg-config
  ];

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wayland-scanner
    shaderc # glslc compiler for Vulkan shaders
    xxd # binary-to-C-header converter for Vulkan shaders
  ];

  buildInputs = [
    bash-completion
    exiv2
    fontconfig
    freetype
    giflib
    libavif
    libdrm
    libheif
    libjpeg
    libjxl
    libpng
    libraw
    librsvg
    libsixel
    libtiff
    libwebp
    libxkbcommon
    luajit
    openexr
    vulkan-headers
    vulkan-loader
    wayland
    wayland-protocols
  ];

  meta = {
    description = "Image viewer for Wayland (forked from artemsen/swayimg, Vulkan-accelerated)";
    homepage = "https://github.com/neg-serg/swayimg";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "swayimg";
  };
})
