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

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/midi2sheet
    install -m 0644 ${./split.py} $out/lib/midi2sheet/split.py
    install -m 0644 ${./patch_title.py} $out/lib/midi2sheet/patch_title.py
    install -m 0755 ${./midi2sheet.sh} $out/lib/midi2sheet/midi2sheet.sh

    makeWrapper $out/lib/midi2sheet/midi2sheet.sh $out/bin/midi2sheet \
      --prefix PATH : ${
        lib.makeBinPath [
          musescore
          pkgs.xvfb-run
          pkgs.python3
          pkgs.coreutils
        ]
      } \
      --set LIB $out/lib/midi2sheet

    runHook postInstall
  '';

  meta = with lib; {
    description = "MIDI to sheet music PDF: pitch-split piano into grand staff, engrave with headless MuseScore";
    homepage = "https://musescore.org";
    license = licenses.mit; # split.py (own code); MuseScore runtime is GPL-3.0+
    platforms = platforms.linux;
    mainProgram = "midi2sheet";
  };
}
