{
  pkgs,
  lib,
  config,
  ...
}: let
  # Fix older CMake policy expectations in alure to avoid build failure with newer CMake
  alureFixed = pkgs.alure.overrideAttrs (prev: {
    cmakeFlags = (prev.cmakeFlags or []) ++ ["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"];
  });
  # Rebuild bucklespring against the fixed alure
  bucklespringFixed = pkgs.bucklespring.overrideAttrs (prev: {
    buildInputs = let bi = prev.buildInputs or []; in lib.unique ((lib.remove pkgs.alure bi) ++ [alureFixed]);
  });
in {
  home.packages = config.lib.neg.pkgsList [
    pkgs.almonds # TUI fractal viewer
    bucklespringFixed # for keyboard sounds
    pkgs.cool-retro-term # a retro terminal emulator
    pkgs.dotacat # yet another color version of cat
    pkgs.figlet # ascii art
    pkgs.fortune # fortune cookie
    pkgs.free42 # A software clone of HP-42S Calculator
    pkgs.neo-cowsay # say something
    pkgs.neo # yet another digital rain
    pkgs.neg.cxxmatrix # colorful matrix rain (C++ impl)
    pkgs.nms # No More Secrets, a recreation of the live decryption effect from the famous hacker movie "Sneakers"
    pkgs.solfege # ear training program
    pkgs.taoup # The Tao of Unix Programming
    pkgs.toilet # text banners
    pkgs.xephem # astronomy app
    pkgs.xlife # cellular automata
  ];
}
