##
# Package: questyle-ctl
# Purpose: Inspect and drive the Questyle QCC Dongle Pro2 (USB 0a12:4007). `info`
#   prints what the kernel, ALSA and PipeWire see; `watch` dumps the vendor HID
#   channel (usage page 0xFF00) read-only, `raw` sends a report by hand and
#   `feature` runs GET_REPORT. The vendor protocol is undocumented, so the tool
#   exists to keep that channel reachable from Linux.
#
# Rust, no crates: the hidraw ioctls, poll and localtime are the libc ones.
# Port of modules/hardware/audio/questyle/questyle-ctl.py, output-compatible.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "questyle-ctl";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Inspect and drive the Questyle QCC Dongle Pro2 (USB 0a12:4007)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "questyle-ctl";
  };
}
