{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-kbdlayout";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The tests are hermetic: a fake `hyprctl` and a fake `socat` (generated
  # shell scripts), a real bound Unix socket for the discovery paths, and
  # temporary directories for the FIFO and the LED stand-ins. Run them in the
  # package build instead of letting them rot.
  doCheck = true;

  meta = lib.mkMeta {
    description = "pleamar keyboard-layout worker (hyprctl, JSON lines)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-kbdlayout";
  };
}
