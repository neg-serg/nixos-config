{
  pkgs,
  lib,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.ffmpeg-full # complete multimedia framework
    pkgs.gmic # image processing framework
  ];
}
