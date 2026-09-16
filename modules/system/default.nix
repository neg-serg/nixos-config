{ neg, ... }:
{
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
    exclude = [
      "disabled-modules.nix" # imported directly by flake/nixos.nix (commonModules, outside domain filter)
    ];
  };
}
