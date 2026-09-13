{
  lib,
  pkgs,
  musescore ? pkgs.musescore, # MuseScore Studio (plain nixpkgs build by default; see overlay)
  ...
}:

# midi2sheet: MIDI -> sheet music PDF (piano grand staff).
# split.py (own code, MIT) splits the input by pitch; headless MuseScore
# (GPL-3.0+ runtime dependency) engraves the score under Xvfb.
pkgs.stdenv.mkDerivation {
  pname = "midi2sheet";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  installPhase =
    builtins.replaceStrings
      [ "@PY@" "@PY_V2@" "@SH@" "@COREUTILS@" ]
      [
        "${./split.py}"
        "${./patch_title.py}"
        "${./midi2sheet.sh}"
        "${lib.makeBinPath [
          musescore
          pkgs.xvfb-run
          pkgs.python3
          pkgs.coreutils
        ]}"
      ]
      (builtins.readFile ./install.sh);

  meta = with lib; {
    description = "MIDI to sheet music PDF: pitch-split piano into grand staff, engrave with headless MuseScore";
    homepage = "https://musescore.org";
    license = licenses.mit; # split.py (own code); MuseScore runtime is GPL-3.0+
    platforms = platforms.linux;
    mainProgram = "midi2sheet";
  };
}
