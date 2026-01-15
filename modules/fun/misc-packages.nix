##
# Module: fun/misc-packages
# Purpose: Provide novelty/entertainment utilities (matrix rain, fortunes, astronomy apps, etc.).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.features.fun.enable or false;
  alureFixed = pkgs.alure.overrideAttrs (prev: {
    # patched to build with new CMake policy
    cmakeFlags = (prev.cmakeFlags or [ ]) ++ [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];
  });
  bucklespringFixed = pkgs.bucklespring.overrideAttrs (prev: {
    # rewire Bucklespring to use fixed alure
    buildInputs =
      let
        bi = prev.buildInputs or [ ];
      in
      lib.unique ((lib.remove pkgs.alure bi) ++ [ alureFixed ]);
  });
  packages = [
    pkgs.almonds # TUI fractal viewer
    bucklespringFixed # keyboard click sound daemon
    pkgs.cool-retro-term # retro CRT terminal emulator
    pkgs.dotacat # colorful `cat`
    pkgs.figlet # ASCII art banners
    pkgs.fortune # fortune cookie
    pkgs.free42 # HP-42S calculator clone
    pkgs.neo-cowsay # render cowsay balloons
    pkgs.neo # digital rain
    pkgs.neg.cxxmatrix # colorful matrix rain (C++ impl)
    pkgs.nms # "No More Secrets" decrypt effect
    pkgs.taoup # The Tao of Unix Programming
    pkgs.toilet # text banners
    pkgs.xephem # astronomy application
    pkgs.xlife # cellular automata explorer
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
