##
# Package: pleamar-fixtures
# Purpose: The D-Bus fixtures the pleamar engine tests run by hand — an MPRIS
#   player whose CanGoNext/CanPlay/... answers are arguments (for the dimmed
#   transport button), and a StatusNotifierItem whose dbusmenu has a parent with
#   children, a separator, a checkable leaf and one action (for the tray menu
#   walk). Ports of files/pleamar/scripts/fixtures/{mpris-stub,tray-nested}.py.
#
# Rust (zbus, blocking): each fixture owns its bus name and serves until
# killed; `tray-nested --once` exits after the first click, like the Python
# script's GLib loop quit.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-fixtures";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "D-Bus fixtures for the pleamar engine: an MPRIS player and a nested tray item";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "mpris-stub";
  };
}
