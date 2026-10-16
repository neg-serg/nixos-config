{
  lib,
  rustPlatform,
}:

# nixbuild-status: one-line NixOS build status for status bars (waybar, i3bar,
# polybar). Detection is /proc- plus Nix-log-based: no `nix` subprocess, no
# network, no daemon, and no crate dependencies, so a single run costs a few
# milliseconds and is safe to use as a panel interval command.
rustPlatform.buildRustPackage {
  pname = "nixbuild-status";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "One-line NixOS build status for status bars (waybar/i3bar/polybar)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "nixbuild-status";
  };
}
