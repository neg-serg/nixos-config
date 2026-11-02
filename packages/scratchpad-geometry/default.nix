##
# Package: scratchpad-geometry
# Purpose: Persist Hyprland scratchpad geometry across show/hide cycles (host
#   trantor). A user-session daemon: it tails the Hyprland IPC socket2 stream,
#   polls `hyprctl clients -j` for drags and resizes, keeps the rects in
#   `~/.local/state/hyprscratch/geometry.json` and re-applies them through the
#   Lua dispatchers when a `special:*` workspace is shown.
#
# Rust, no crates. `hyprctl` is put on PATH by the wrapper because a systemd
# user service runs with a minimal environment; the client itself only shells
# out to it. `SCRATCHPAD_GEOMETRY_HYPR_DIR` overrides the runtime directory,
# which is what makes the daemon testable against a fake instance.
{
  lib,
  rustPlatform,
  makeWrapper,
  hyprland,
}:

rustPlatform.buildRustPackage {
  pname = "scratchpad-geometry";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/scratchpad-geometry \
      --prefix PATH : ${lib.makeBinPath [ hyprland ]}
  '';

  meta = lib.mkMeta {
    description = "Persist Hyprland scratchpad geometry across show/hide cycles";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "scratchpad-geometry";
  };
}
