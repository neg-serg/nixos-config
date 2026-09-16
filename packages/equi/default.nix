##
# Package: equi
# Purpose: EQui — SuperCollider quark, a 7-band parametric EQ with GUI for
#   UGens and Ndefs. The thgrund fork (master) is required by SuperDirtMixer.
# Source: https://github.com/thgrund/EQui
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "equi";
  version = "1.0.0-unstable-2024-10-13";

  url = "https://github.com/thgrund/EQui.git";
  rev = "95623d0ea658b4d1cf9db8690e966a824915547e";
  hash = "sha256-X2XPso5RSMf4ZYGcqV9MrdCngePDPt1db4s+nAP9X/Y=";

  installDir = "EQui";
  install = ''
    cp -r EQui.sc "$extdir/"
    cp -r HelpSource "$extdir/"
    cp EQui.quark "$extdir/"
    cp README.md "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: 7-band parametric EQ with GUI for UGens and Ndefs (thgrund fork)";
    longDescription = ''
      EQui is a SuperCollider quark providing a parametric equalizer with a
      graphical user interface. This fork (thgrund/EQui master) is a
      dependency of SuperDirtMixer; the original project is by Scott Wilson.
    '';
    homepage = "https://github.com/thgrund/EQui";
    license = lib.licenses.gpl3Plus; # EQui.quark declares license: GPL
    platforms = lib.platforms.linux;
  };
}
