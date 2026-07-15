# game — Unified game launcher (Rust).
#
# Replaces: game-run, game-affinity-exec, gamescope-{perf,quality,hdr,targetfps,pinned},
# game-pinned, game-session, game-session-mangohud, gamescope-run, gamescope-app.
#
# Subcommands:
#   game run [--cpus <set>] [--no-gamemode] [--no-pin] [--dry-run] -- <command>
#   game scope [--preset <name>] [--scale <f>] [--hdr] ... -- <command>
#   game session [--mangohud] [--no-hdr] [--no-pin]
#   game app -r <res> [--filter <f>] [--fullscreen] -- <command>
#   game info [--json]

{
  pkgs,
  lib,
  ...
}:

let
  version = "0.1.0";
  pname = "game";
in
pkgs.rustPlatform.buildRustPackage {
  inherit pname version;

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [ ];

  meta = {
    description = "Unified game launcher — CPU pinning, Gamescope presets, session launching";
    longDescription = ''
      One binary to replace all game scripts: CPU affinity with V-Cache auto-detection,
      systemd-run with games.slice, Gamescope presets (perf/quality/hdr/targetfps),
      Steam Big Picture session launcher, desktop app mode, and TOML configuration.
      Supports FSR upscaling, HDR, adaptive sync, per-game config via Steam AppID.
    '';
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = lib.platforms.linux;
    mainProgram = "game";
  };
}
