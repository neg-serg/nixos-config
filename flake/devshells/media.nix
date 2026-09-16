{ pkgs, ... }: {
  nativeBuildInputs = [
    pkgs.ffmpeg-full # complete multimedia framework
    pkgs.gmic # image processing framework
  ];
}
