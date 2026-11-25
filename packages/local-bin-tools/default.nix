##
# Package: local-bin-tools
# Purpose: Small `$PATH` helpers, mostly Rust ports of the
#   packages/local-bin/{bin,scripts} originals: `paths`, `window-activate`,
#   `menu-search`, `surfingkeys-server`, `ren`, `fetch-covers` (album covers
#   via sacad) and `gen-unbound-hosts` (regenerates
#   hosts/trantor/unbound-hosts.nix; `just unbound-hosts` runs it), plus
#   `dsh-worktree`. One multicall binary answers to all eight names.
#
# Crates: `serde_json` and `sha1`, used only by `dsh-worktree`.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "local-bin-tools";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # One multicall binary; each command is an argv[0] name pointing at it.
  postInstall = ''
    for name in gen-unbound-hosts fetch-covers ren menu-search paths window-activate surfingkeys-server dsh-worktree; do
      ln -s local-bin-tools "$out/bin/$name"
    done
  '';

  meta = lib.mkMeta {
    description = "Small $PATH helpers (album covers, unbound host entries), shipped as one multicall binary";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "gen-unbound-hosts";
  };
}
