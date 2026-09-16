##
# Package: timestretch
# Purpose: TimeStretch — SC quark by Sam Pluta: extreme time stretch based on
#   the Ness Stretch layered STFT algorithm (9 frequency bands, decreasing
#   frame sizes). Pure sclang classes (TimeStretch, TimeStretch2) + help.
# Source: https://github.com/spluta/TimeStretch
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "timestretch";
  version = "1.5.0-unstable-2023-09-16";

  owner = "spluta";
  repo = "TimeStretch";
  rev = "e8b7ab3a0ffb3152380c6be38515410fd6afa00a";
  hash = "sha256-Uw525EvAzAR2Gd8aL8q7lqPxi+A3TBAFZOf58ESdJW4=";

  installDir = "TimeStretch";
  install = ''
    cp -r supercollider/Classes "$extdir/"
    cp -r supercollider/HelpSource "$extdir/"
    cp TimeStretch.quark LICENSE "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: extreme time stretch (Ness Stretch layered STFT algorithm)";
    homepage = "https://github.com/spluta/TimeStretch";
    license = lib.licenses.gpl3Plus; # quark manifest says GPLv3
  };
}
