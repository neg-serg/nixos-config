##
# Package: hypr-win-list
# Purpose: List Hyprland windows in a vicinae dmenu picker and focus the chosen
#   one. One line per window — `<glyph> <title> (<workspace>) — <address>` —
#   with special workspaces, unmapped windows and the focused window hidden.
#
# Rust, no crates: `hyprctl` and `vicinae` are shelled out to, the JSON is read
#   in-crate. Both binaries land on PATH through the wrapper, because the tool
#   is started from a Hyprland key binding, where the environment is minimal.
{
  lib,
  rustPlatform,
  makeWrapper,
  hyprland,
  vicinae,
}:

rustPlatform.buildRustPackage {
  pname = "hypr-win-list";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/hypr-win-list \
      --prefix PATH : ${
        lib.makeBinPath [
          hyprland
          vicinae
        ]
      }
  '';

  meta = lib.mkMeta {
    description = "Hyprland window picker for vicinae dmenu";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "hypr-win-list";
  };
}
