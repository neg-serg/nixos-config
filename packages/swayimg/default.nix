{
  lib,
  stdenv,
  fetchFromGitHub,
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
  bash-completion,
  vulkan-headers,
  vulkan-loader,
  shaderc,
  xxd,
}:

stdenv.mkDerivation (_finalAttrs: {
  pname = "swayimg";
  version = "0-unstable-fork";

  # Pinned to a commit (was floating master.tar.gz)
  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "swayimg";
    rev = "9fb73f6fad02cbe003db75b32f31a4ab4153e7d2";
    hash = "sha256-DYt58kkGR+9Yu6neqJQYH2PRwt3dkWMDCfGsALR36jQ=";
  };

  # upstream removed icon_128/256.png but kept the install rules —
  # drop the dead install targets (packages/swayimg-meson-icons.patch)
  patches = [ ./../swayimg-meson-icons.patch ];

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
    maintainers = [ ];
  };
})
