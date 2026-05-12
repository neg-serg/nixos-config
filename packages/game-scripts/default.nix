# Game Scripts Package
#
# Consolidates all gaming-related scripts (gamescope wrappers, CPU affinity tools)
# into a single derivation. Replaces the inline script definitions that were
# previously scattered in modules/user/games/default.nix.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Default CPU pin set for affinity wrappers
  # Falls back to 'auto' to detect V-Cache CCD via L3 size at runtime
  pinDefault =
    let
      v = config.profiles.performance.gamingCpuSet or "";
    in
    if v != "" then v else "auto";

  scriptsDir = ./.;
in
{
  # Gamescope preset wrappers
  gamescope-pinned = pkgs.writers.writePython3Bin "gamescope-pinned" { } (
    builtins.readFile (scriptsDir + "/gamescope-pinned.py")
  );

  game-pinned = pkgs.writers.writePython3Bin "game-pinned" { } (
    builtins.readFile (scriptsDir + "/game-pinned.py")
  );

  gamescope-perf = pkgs.writers.writePython3Bin "gamescope-perf" { } (
    builtins.readFile (scriptsDir + "/gamescope-perf.py")
  );

  gamescope-quality = pkgs.writers.writePython3Bin "gamescope-quality" { } (
    builtins.readFile (scriptsDir + "/gamescope-quality.py")
  );

  gamescope-hdr = pkgs.writers.writePython3Bin "gamescope-hdr" { } (
    builtins.readFile (scriptsDir + "/gamescope-hdr.py")
  );

  gamescope-targetfps = pkgs.writers.writePython3Bin "gamescope-targetfps" { } (
    builtins.readFile (scriptsDir + "/gamescope-targetfps.py")
  );

  # CPU affinity helpers
  game-affinity-exec = pkgs.writers.writePython3Bin "game-affinity-exec" { } (
    lib.replaceStrings [ "\${pinDefault}" ] [ pinDefault ] (
      builtins.readFile (scriptsDir + "/game_affinity_exec.py")
    )
  );

  game-run = pkgs.writers.writePython3Bin "game-run" { } (
    lib.replaceStrings [ "@pinDefault@" ] [ pinDefault ] (
      builtins.readFile (scriptsDir + "/game_run.py")
    )
  );

  # SteamVR launcher
  steamvr = pkgs.writeShellApplication {
    name = "steamvr";
    text = builtins.readFile (scriptsDir + "/steamvr.sh");
  };
}
