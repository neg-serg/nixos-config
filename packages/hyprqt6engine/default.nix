# hyprqt6engine — Qt6 platform theme + widget style for Hyprland; a drop-in
# replacement for qt6ct that reads the Hyprland/hyprqt6engine config. Not in the
# pinned nixpkgs yet (checked 2026-10: no pkgs/by-name/hy/hyprqt6engine), so it
# is pinned here. To bump: new tag in src.tag, refresh src.hash
# (`nix store prefetch-file --unpack --json <tarball>`), and re-check the Qt6
# minimum in CMakeLists.txt (currently 6.9). The KF6 packages are optional in
# upstream CMake, so this build ships without KDE color-scheme/icon-theme
# support; add kdePackages.kconfig/kcolorscheme/kiconthemes if that is needed.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  hyprlang,
  hyprutils,
  qt6,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hyprqt6engine";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprqt6engine";
    tag = "v${finalAttrs.version}";
    hash = "sha256-WSUMQmfVlpz31o2Tgfue0jnVRCeTrRi3Cy6s2/o8hzQ=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    hyprlang
    hyprutils
    qt6.qtbase
  ];

  # The build produces QPA/style plugins, not apps, so there is nothing to wrap;
  # PLUGINDIR is passed explicitly because the CMake fallback probes qtpaths,
  # which is not on PATH here.
  dontWrapQtApps = true;
  cmakeFlags = [
    (lib.cmakeFeature "PLUGINDIR" "${placeholder "out"}/${qt6.qtbase.qtPluginPrefix}")
  ];

  meta = lib.mkMeta {
    description = "Qt6 theme provider for Hyprland (platform theme + widget style)";
    homepage = "https://github.com/hyprwm/hyprqt6engine";
    license = lib.licenses.bsd3;
    maintainers = [ lib.maintainers.fufexan ];
  };
})
