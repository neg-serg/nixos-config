{
  lib,
  stdenv,
  alsa-lib,
}:
stdenv.mkDerivation {
  pname = "virtual-midi";
  version = "0.1.0";
  src = ./.;
  buildInputs = [ alsa-lib ];
  installPhase = ''
    mkdir -p $out/bin
    $CC -O2 -o $out/bin/virtual-midi virtual-midi.c -lasound
  '';
  meta = {
    description = "Virtual ALSA sequencer MIDI ports (user-space snd-virmidi)";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
