# qs-wallpaperpicker — swatch-deck wallpaper picker for Quickshell
# (https://github.com/dhrruvsharma/qs-wallpaperpicker, vendored under
# files/qs-wallpaperpicker at export 3cfae35).
#
# The picker is a Quickshell config of its own — `qs -p
# ~/.config/qs-wallpaperpicker`, IPC target `wallpaper` — so this package ships
# only the CLI that the session unit and the keybind call. The QML tree itself is
# deployed by modules/user/nix-maid/gui/wallpaper-picker.nix instead of being run
# from the store: the picker writes settings.json and matugen writes
# colors/Colors.json inside its config directory, which a store path cannot take.
#
# The `qs` it execs is the repo's wrapped Quickshell (lib/quickshell-wrapper.nix,
# the same pinned flake input the bar and the greeter run). That wrapper's PATH is
# where the picker finds everything it shells out to: python3 for
# scripts/wallpaper-palettes.py, ffmpeg for a video's still frame, curl for
# Wallhaven, matugen for the cards' colour schemes, hyprctl to pause a video
# wallpaper under a window, and wl for the wallpaper command the settings seed
# points at.
{
  pkgs,
  lib,
  paths,
  inputs,
  wl,
}:

let
  # Same source the bar and the greeter run (post-0.3.0 crash fixes).
  qsPkg = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;

  qsWrapped = (import (paths.path "lib/quickshell-wrapper.nix") { inherit lib pkgs; }) {
    inherit qsPkg;
    extraPath = [
      pkgs.bash # the picker's own scripts run under a bash shebang
      pkgs.coreutils # readlink, md5sum, nice, mktemp and seq in those scripts
      pkgs.curl # Wallhaven search and downloads
      pkgs.ffmpeg # scripts/wallpaper-still: a frame of a video wallpaper
      pkgs.hyprland # hyprctl: pause a video wallpaper under a window
      pkgs.matugen # the deck's colours, and the palette behind a set wallpaper
      pkgs.python3 # scripts/wallpaper-palettes.py
      wl # `wl img {}`: the daemon paints, the picker only chooses
    ];
  };
in
pkgs.stdenv.mkDerivation {
  pname = "qs-wallpaperpicker";
  version = "0-unstable-2026-10-11";

  src = paths.path "files/qs-wallpaperpicker";

  nativeBuildInputs = [ pkgs.makeWrapper ];

  # bin/qs-wallpaperpicker is upstream's CLI unchanged; the tree beside it is
  # deployed by nix-maid, so nothing else belongs in the output.
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/qs-wallpaperpicker $out/bin/qs-wallpaperpicker
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/qs-wallpaperpicker --prefix PATH : ${lib.makeBinPath [ qsWrapped ]}
  '';

  meta = lib.mkMeta {
    description = "Swatch-deck wallpaper picker for Quickshell";
    homepage = "https://github.com/dhrruvsharma/qs-wallpaperpicker";
    license = lib.licenses.gpl3Plus;
    mainProgram = "qs-wallpaperpicker";
  };
}
