##
# Package: hypr-rearrange
# Purpose: Move Hyprland windows onto the workspaces the config routes them to.
#   Reads the routing rules from `hyprland.lua` (the `cls` / `routes` tables),
#   falls back to the legacy `windowrule` lines of `hyprland.conf`, then moves
#   every client whose class or title matches with one `hyprctl --batch` call.
#   `--dry-run` prints the dispatches instead.
#
# Rust, no crates: `hyprctl` is shelled out to, the JSON is read in-crate and
# the class/title patterns go through a small matcher for the subset Hyprland
# rules use. hyprctl lands on PATH through the wrapper (a user-session tool has
# no guarantee of it).
{
  lib,
  rustPlatform,
  makeWrapper,
  hyprland,
}:

rustPlatform.buildRustPackage {
  pname = "hypr-rearrange";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/hypr-rearrange \
      --prefix PATH : ${lib.makeBinPath [ hyprland ]}
  '';

  meta = lib.mkMeta {
    description = "Move Hyprland windows to the workspaces the config routes them to";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "hypr-rearrange";
  };
}
