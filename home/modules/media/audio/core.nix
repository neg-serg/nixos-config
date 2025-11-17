{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf config.features.media.audio.core.enable {
  home.packages = config.lib.neg.pkgsList [
    # utils
    pkgs.alsa-utils # ALSA CLI utilities (amixer, aplay)
    pkgs.coppwr # PipeWire/Audio helper (misc utilities)
    pkgs.pw-volume # PipeWire volume control CLI
    pkgs.pwvucontrol # PipeWire volume control GUI
    # routers
    pkgs.helvum # GTK patchbay for PipeWire
    pkgs.qpwgraph # Qt patchbay for PipeWire
    pkgs.open-music-kontrollers.patchmatrix # JACK/PipeWire patchbay
  ];
}
