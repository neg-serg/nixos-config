{ pkgs, ... }: {
  nativeBuildInputs = [
    pkgs.ffmpeg-full # complete multimedia framework
    pkgs.gmic # image processing framework
    # Moved out of the system closure (a 2.7G torch env): audio→MIDI
    # transcription, also available as `nix run .#midi-transcribe`.
    pkgs.neg.midi-transcribe
  ];
}
