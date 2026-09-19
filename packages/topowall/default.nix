##
# Package: topowall
# Purpose: topographic contour wallpapers from real elevation data — fetches
#   terrain tiles for any place on Earth and renders contour lines on the GPU
#   (wgpu: Vulkan/OpenGL), in built-in palettes, terminal color schemes,
#   image-derived palettes or a user shader.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  vulkan-loader,
  libGL,
  wayland,
  libxkbcommon,
}:

rustPlatform.buildRustPackage rec {
  pname = "topowall";
  version = "0.3.0";

  # v0.3.0 (pinned to the commit the tag points at).
  src = fetchFromGitHub {
    owner = "gonzalezerik";
    repo = "topowall";
    rev = "f4f9c6a8ff643b9c2e62e6db6fa31e1039d726f7";
    hash = "sha256-zdR240BuFZQK+jix62UL4qnOanmI+PwDLtagKtsIdVo=";
  };

  cargoHash = "sha256-8cXBENHzZwVeMV0nqIV6x7s+Vsfm3EL5YaB0jNynJRY=";

  nativeBuildInputs = [ makeWrapper ];

  # wgpu picks its graphics API through dlopen (libvulkan.so.1, libEGL/libGL),
  # which a RUNPATH does not cover, so the wrappers below put them on
  # LD_LIBRARY_PATH — the same runtime library set upstream's flake.nix uses.
  postFixup = ''
    wrapProgram $out/bin/topowall \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          vulkan-loader
          libGL
          wayland
          libxkbcommon
        ]
      }
  '';

  meta = lib.mkMeta {
    description = "Topographic contour wallpapers from real elevation data, rendered on the GPU";
    longDescription = ''
      CLI for building contour-line wallpapers out of real elevation data:
      `fetch` downloads terrain tiles for the chosen area into a .topo
      heightmap, `render` draws the contour map on the GPU, `theme`/`palettes`
      turn a color scheme or an image into line colors. Also used to check
      which GPU (or software renderer) topowall would render on.
    '';
    homepage = "https://github.com/gonzalezerik/topowall";
    license = lib.licenses.mit;
    mainProgram = "topowall";
  };
}
