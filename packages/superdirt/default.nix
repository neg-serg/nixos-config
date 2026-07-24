##
# Package: superdirt
# Purpose: SuperDirt — SuperCollider quark, the audio engine for TidalCycles.
#   Provides synth definitions, effects, and the SuperDirt class library.
# Source: https://codeberg.org/musikinformatik/SuperDirt
{
  lib,
  stdenvNoCC,
  fetchgit,
}:
stdenvNoCC.mkDerivation {
  pname = "superdirt";
  version = "1.7.4-unstable-2025-07-21";

  src = fetchgit {
    url = "https://codeberg.org/musikinformatik/SuperDirt.git";
    rev = "33f4040423967373c4cc9855b90c951ce93ca2e0";
    hash = "sha256-Yeuackq9Mvk8I/Td5o0T+WZPYI5JZ5BgGc5i7xTby5g=";
  };

  installPhase = ''
    runHook preInstall

    # SuperCollider looks for extensions in a fixed layout:
    #   $out/share/SuperCollider/extensions/<QuarkName>/
    extdir="$out/share/SuperCollider/extensions/SuperDirt"
    mkdir -p "$extdir"

    # Copy class files (the actual SC code)
    cp -r classes "$extdir/"
    # Copy synth definitions (SynthDef files)
    cp -r synths "$extdir/"
    # Copy help source
    cp -r HelpSource "$extdir/"
    # Copy library support scripts
    cp -r library "$extdir/"
    # Copy the quark manifest
    cp SuperDirt.quark "$extdir/"
    cp LICENSE README.md "$extdir/" 2>/dev/null || true

    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark providing the audio engine for TidalCycles live coding";
    longDescription = ''
      SuperDirt is a SuperCollider-based audio synthesis engine designed
      to work with TidalCycles. It provides a large library of sample-based
      and synthesized sounds, effects, and routing, controlled via OSC
      messages from TidalCycles pattern language.
    '';
    homepage = "https://codeberg.org/musikinformatik/SuperDirt";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
