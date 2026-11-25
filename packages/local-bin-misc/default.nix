##
# Package: local-bin-misc
# Purpose: Rust ports of the last shell helpers in `packages/local-bin/bin`:
#   pb (pastebin upload), any (pgrep -> ps), v (attach to the Neovim server or
#   start one), sclang-pwj (sclang under PipeWire-JACK) and renoise-pwj
#   (Renoise launcher). One binary per former script, installed under the
#   script's own name, so `~/.local/bin` can point at the store paths instead
#   of rendering the shell files.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-misc";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Rust ports of the last packages/local-bin/bin helpers (pb, any, v, sclang-pwj, renoise-pwj)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pb";
  };
}
