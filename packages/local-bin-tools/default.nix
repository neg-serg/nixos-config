##
# Package: local-bin-tools
# Purpose: Small `$PATH` helpers, mostly Rust ports of the
#   packages/local-bin/{bin,scripts} originals: `paths`, `window-activate`,
#   `menu-search`, `surfingkeys-server`, `ren`, `fetch-covers` (album covers
#   via sacad) and `gen-unbound-hosts` (regenerates
#   hosts/trantor/unbound-hosts.nix; `just unbound-hosts` runs it), plus
#   `dsh-worktree`.
#
# Crates: `serde_json` and `sha1`, used only by `dsh-worktree`.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "local-bin-tools";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Small $PATH helpers (album covers, unbound host entries)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "gen-unbound-hosts";
  };
}
