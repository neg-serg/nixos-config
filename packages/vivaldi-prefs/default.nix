##
# Package: vivaldi-prefs
# Purpose: Re-assert the managed Vivaldi preferences before the browser starts
#   (CSS mods directory, Neg dark theme, hidden panel bar, UI auto-hide off,
#   Ctrl+W freed / Ctrl+G closes the tab, dark new-tab extension). Vivaldi
#   rewrites `Preferences` from memory on exit, so this runs from a systemd user
#   unit ahead of the browser; only differing keys are touched and the file is
#   written back with Vivaldi's own `indent=1` formatting.
#
# Rust, no crates: the profile is a JSON document, read and rewritten by the
# small order-preserving reader/writer in the crate, which keeps unchanged
# values (including the int/float spelling) exactly as they were.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "vivaldi-prefs";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Re-assert Vivaldi preferences before the browser starts";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "vivaldi-prefs";
  };
}
