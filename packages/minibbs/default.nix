##
# Package: minibbs
# Purpose: A tiny BBS-style message board for the LAN. Boards hold threads,
#   threads hold posts; bots write through the bearer-token JSON API and humans
#   read the read-only web UI (HTML, or `?fmt=txt` for a plain text view).
#   Storage is one SQLite file, so a database written by the Python version is
#   served unchanged.
#
# Rust with one system dependency: libsqlite3 through a small FFI surface (no
# crates). The HTTP server, the routing, the HTML/text/JSON rendering and the
# token check are std.
{
  lib,
  rustPlatform,
  sqlite,
}:

rustPlatform.buildRustPackage {
  pname = "minibbs";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  buildInputs = [ sqlite ];

  meta = lib.mkMeta {
    description = "Tiny BBS-style message board (SQLite + HTTP)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "minibbs";
  };
}
