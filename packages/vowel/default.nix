##
# Package: vowel
# Purpose: Vowel — SuperCollider quark with formant tables (Vowel class),
#   used by SuperDirt's default synths (vowel synth defs) at runtime.
# Source: https://github.com/supercollider-quarks/Vowel
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "vowel";
  version = "unstable-2025-07-25";

  src = fetchFromGitHub {
    owner = "supercollider-quarks";
    repo = "Vowel";
    rev = "ab59caa870201ecf2604b3efdd2196e21a8b5446";
    hash = "sha256-zfF6cvAGDNYWYsE8dOIo38b+dIymd17Pexg0HiPFbxM=";
  };

  installPhase = ''
    runHook preInstall

    # SuperCollider looks for extensions in a fixed layout:
    #   $out/share/SuperCollider/extensions/<QuarkName>/
    extdir="$out/share/SuperCollider/extensions/Vowel"
    mkdir -p "$extdir"

    # Class files (the actual formant data + Vowel class)
    cp Vowel.sc Formants.sc "$extdir/"
    # Help source
    cp -r HelpSource "$extdir/"
    # Quark manifest + license
    cp Vowel.quark LICENSE "$extdir/"

    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark with formant tables (Vowel class), used by SuperDirt";
    longDescription = ''
      Vowel provides the Vowel class with formant frequency tables for a
      range of voice registers. SuperDirt's default synth definitions call
      Vowel.formLib at startup, so this quark must be present on the SC
      class path for the vowel-based synths to work.
    '';
    homepage = "https://github.com/supercollider-quarks/Vowel";
    license = licenses.lgpl21Plus; # GNU LGPL 2.1
    platforms = platforms.all;
    maintainers = [ ];
  };
}
