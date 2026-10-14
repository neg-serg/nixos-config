# hypr-kdeconnect-fix — user-level xdg-desktop-portal RemoteDesktop backend.
#
# KDE Connect (and Deskflow) inject remote pointer/keyboard input through
# org.freedesktop.portal.RemoteDesktop, but the Hyprland portal backend does
# not implement that interface. This bridge implements it and feeds the events
# into Hyprland's virtual-input protocols (zwlr_virtual_pointer_v1,
# zwp_virtual_keyboard_v1), including the libei ConnectToEIS path that KDE
# Connect 26.04+ prefers.
#
# Upstream publishes no tags, so the pin is a master rev; to bump: new `src.rev`
# and refresh `src.hash` (`nix store prefetch-file --unpack <tarball>`).
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  wayland-scanner,
  qt6,
  libei,
  libxkbcommon,
  wayland,
}:

stdenv.mkDerivation {
  pname = "hypr-kdeconnect-fix";
  version = "0.1.0-unstable-2026-10-05";

  src = fetchFromGitHub {
    owner = "gfhdhytghd";
    repo = "hypr-kdeconnect-fix";
    rev = "5fc959475177197f0aa953fcc42a3742e6648671";
    hash = "sha256-vhb+UMDJXvw8PAIzH1bsLk4JmXzRIPiFTRQxZX3wPZM=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    wayland-scanner # compiles the bundled virtual-keyboard / wlr-virtual-pointer XML
  ];

  buildInputs = [
    qt6.qtbase # Core + DBus
    libei # pkg-config modules libeis-1.0 (runtime) and libei-1.0 (tests)
    libxkbcommon
    wayland # wayland-client
  ];

  # Headless D-Bus service: QtCore/QtDBus only (QCoreApplication, no GUI), so
  # the Qt setup hook's wrapping (QT_PLUGIN_PATH/QML) buys nothing — the hook
  # still wants the choice spelled out.
  dontWrapQtApps = true;

  # CTest suite: key resolver, D-Bus/session security policy, the EIS input
  # bridge, the generated portal metadata and PIE/hardening flags.
  doCheck = true;

  meta = lib.mkMeta {
    description = "xdg-desktop-portal RemoteDesktop backend for KDE Connect on virtual-input Wayland compositors";
    homepage = "https://github.com/gfhdhytghd/hypr-kdeconnect-fix";
    license = lib.licenses.mit;
    mainProgram = "hypr-kdeconnect-portal";
  };
}
