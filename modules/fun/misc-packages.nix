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

    bucklespringFixed # keyboard click sound daemon

    pkgs.dotacat # colorful cat implementation in Rust
    pkgs.figlet # program for making large letters out of ordinary text
    pkgs.fortune # program that displays a pseudorandom message from a database of quotations

    pkgs.neo-cowsay # cowsay and cowthink reboot for GNU/Linux
    pkgs.neo # matrix legacy digital rain solution
    pkgs.neg.cxxmatrix # colorful matrix rain (C++ impl)
    pkgs.nms # "No More Secrets" decrypt effect
    pkgs.taoup # The Tao of Unix Programming
    pkgs.toilet # text banners

  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
