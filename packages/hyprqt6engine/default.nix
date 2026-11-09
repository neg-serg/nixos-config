# hyprqt6engine — Qt6 platform theme + widget style for Hyprland; a drop-in
# replacement for qt6ct that reads the Hyprland/hyprqt6engine config. Not in the
# pinned nixpkgs yet (checked 2026-10: no pkgs/by-name/hy/hyprqt6engine), so it
# is pinned here. Pinned to a main rev instead of the v0.1.0 tag: the tag's
# hyprqtplugin/CMakeLists.txt never calls find_package(Qt6 … GuiPrivate), so the
# link fails with "Target Qt6::GuiPrivate was not found"; main (d0ce29ca) adds
# it and bumps nothing else (VERSION is still 0.1.0). To bump: new rev + hash
# (`nix store prefetch-file --unpack --json <tarball>`), re-check the Qt6
# minimum in CMakeLists.txt (currently 6.9), and switch back to a tag once a
# release is cut from main. KF6 support in upstream CMake is optional and every
# use site is #ifdef-guarded; the KF6 pieces are wired in so the platform theme
# runs with its intended features: KF6IconThemes for the icon-theme lookup and
# KF6ConfigCore + KF6ColorScheme for parsing the .colors file named by
# theme:color_scheme (without the latter the palette stays the generic Qt one).
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  hyprlang,
  hyprutils,
  kdePackages,
  qt6,
}:

stdenv.mkDerivation {
  pname = "hyprqt6engine";
  version = "0.1.0-unstable-2026-08-11";

  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprqt6engine";
    rev = "d0ce29ca5471f406c71558cd9453573686b8c976";
    hash = "sha256-UQQue60zRgkz4KqqAyVZlVqGvdGZcj5BuWV9SlbURis=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    hyprlang
    hyprutils
    kdePackages.kcolorscheme # KF6ColorScheme: turns the .colors file into the palette
    kdePackages.kconfig # KF6ConfigCore: KSharedConfig backing KColorScheme
    kdePackages.kiconthemes # KF6IconThemes: icon-theme lookup for the platform theme
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
}
