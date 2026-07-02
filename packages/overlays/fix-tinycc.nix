# repo.or.cz generates non-reproducible tarballs for tinycc snapshots.
# minimal-bootstrap uses its own fetchurl (from boot.nix), not the global one.
# Override minimal-bootstrap entirely with a fixed fetchurl.
_inputs: final: prev:
let
  inherit (final) lib;

  # Boot fetchurl with URL redirection for tinycc
  bootFetchurl = import (prev.path + "/pkgs/build-support/fetchurl/boot.nix") {
    inherit (prev.stdenv.buildPlatform) system;
    inherit (prev.config) rewriteURL;
  };

  fixedFetchurl = args:
    let
      url = args.url or "";
    in
    if lib.hasPrefix "https://repo.or.cz/tinycc.git/snapshot/" url then
      bootFetchurl (args // {
        url = "https://github.com/TinyCC/tinycc/archive/${lib.removePrefix "https://repo.or.cz/tinycc.git/snapshot/" url}";
        hash = "sha256-c4H5RKqSVc1WDoGSxbAkEkbSyD7qVLjrMXECmS/h4rs=";
      })
    else
      bootFetchurl args;
in
{
  minimal-bootstrap = import (prev.path + "/pkgs/os-specific/linux/minimal-bootstrap") {
    inherit (prev.stdenv) buildPlatform hostPlatform;
    inherit (prev) lib;
    config = prev.config;
    fetchurl = fixedFetchurl;
    checkMeta = prev.callPackage (prev.path + "/pkgs/stdenv/generic/check-meta.nix") {
      inherit (prev.stdenv) hostPlatform;
    };
  };
}
