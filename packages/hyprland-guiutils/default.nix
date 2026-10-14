# hyprland-guiutils — the hyprtoolkit-based successor to hyprland-qtutils
# (same five binaries: hyprland-dialog, -donate-screen, -update-screen,
# -welcome, -run). Not in the pinned nixpkgs yet (checked 2026-10: no
# pkgs/by-name/hy/hyprland-guiutils), so it is pinned here. To bump: new tag in
# src.tag, refresh src.hash (`nix store prefetch-file --unpack <tarball>`), and
# re-check the hyprlang/hyprutils/hyprtoolkit minimums in CMakeLists.txt — the
# nixpkgs versions must satisfy them.
{
  lib,
  gcc16Stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  aquamarine,
  cairo,
  hyprgraphics,
  hyprlang,
  hyprtoolkit,
  hyprutils,
  libdrm,
  libGL,
  libxkbcommon,
  pango,
  pixman,
}:

gcc16Stdenv.mkDerivation (finalAttrs: {
  pname = "hyprland-guiutils";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprland-guiutils";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Ee78BRFi+MrmgHmmW+2dZUEI1R3cssEzza0ar3fsNX8=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  # CMake itself only pkg-config-requires hyprlang/hyprutils/hyprtoolkit +
  # pixman/xkbcommon/libdrm; the rest mirror upstream nix/default.nix because
  # they reach the build through hyprtoolkit.
  buildInputs = [
    aquamarine
    cairo
    hyprgraphics
    hyprlang
    hyprtoolkit
    hyprutils
    libdrm
    libGL
    libxkbcommon
    pango
    pixman
  ];

  meta = lib.mkMeta {
    description = "Hyprland GUI utilities (successor to hyprland-qtutils)";
    homepage = "https://github.com/hyprwm/hyprland-guiutils";
    license = lib.licenses.bsd3;
    mainProgram = "hyprland-dialog";
    maintainers = [ lib.maintainers.fufexan ];
  };
})
