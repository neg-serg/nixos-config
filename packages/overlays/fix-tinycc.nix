# repo.or.cz generates non-reproducible tarballs for tinycc snapshots.
# Override fetchurl globally to redirect repo.or.cz URLs to GitHub.
inputs: final: prev:
let
  inherit (final) lib;
in
{
  fetchurl = args:
    let
      url = args.url or "";
    in
    if lib.hasPrefix "https://repo.or.cz/tinycc.git/snapshot/" url then
      prev.fetchurl (args // {
        url = "https://github.com/TinyCC/tinycc/archive/${lib.removePrefix "https://repo.or.cz/tinycc.git/snapshot/" url}";
        hash = "sha256-c4H5RKqSVc1WDoGSxbAkEkbSyD7qVLjrMXECmS/h4rs=";
      })
    else
      prev.fetchurl args;
}
