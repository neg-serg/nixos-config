{ neg, ... }:
{
  # alkano-aio.nix is a package (callPackage from theme.nix), not a module
  imports = neg.importDir {
    dir = ./.;
    exclude = [ "alkano-aio.nix" ];
  };
}
