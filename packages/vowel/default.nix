##
# Package: vowel
# Purpose: Vowel — SuperCollider quark with formant tables (Vowel class),
#   used by SuperDirt's default synths (vowel synth defs) at runtime.
# Source: https://github.com/supercollider-quarks/Vowel
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "vowel";
  version = "unstable-2025-07-25";

  owner = "supercollider-quarks";
  repo = "Vowel";
  rev = "ab59caa870201ecf2604b3efdd2196e21a8b5446";
  hash = "sha256-zfF6cvAGDNYWYsE8dOIo38b+dIymd17Pexg0HiPFbxM=";

  installDir = "Vowel";
  install = ''
    # Class files (the actual formant data + Vowel class)
    cp Vowel.sc Formants.sc "$extdir/"
    # Help source
    cp -r HelpSource "$extdir/"
    # Quark manifest + license
    cp Vowel.quark LICENSE "$extdir/"
  '';

  meta = {
    description = "SuperCollider quark with formant tables (Vowel class), used by SuperDirt";
    longDescription = ''
      Vowel provides the Vowel class with formant frequency tables for a
      range of voice registers. SuperDirt's default synth definitions call
      Vowel.formLib at startup, so this quark must be present on the SC
      class path for the vowel-based synths to work.
    '';
    homepage = "https://github.com/supercollider-quarks/Vowel";
    license = lib.licenses.lgpl21Plus; # GNU LGPL 2.1
  };
}
