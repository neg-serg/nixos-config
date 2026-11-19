{ neg, ... }:
{
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };

  nixpkgs.overlays = [
    (
      final: prev:
      if prev ? fastfetch-unwrapped then
        {
          fastfetch-unwrapped = prev.fastfetch-unwrapped.overrideAttrs (old: {
            # Enable experimental Lua scripting in fastfetch format strings (2.64.0+).
            # lua5_4 explicitly: the unversioned `lua` alias does not exist with
            # allowAliases=false (flake/lib.nix).
            buildInputs = (old.buildInputs or [ ]) ++ [ final.lua5_4 ];
            cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DENABLE_LUA=ON" ];
          });
        }
      else
        { }
    )
  ];
}
