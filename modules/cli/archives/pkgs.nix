{ config, pkgs, ... }:
let
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  environment.systemPackages = [
    pkgs.ouch # archive extractor/creator
    pkgs.patool # universal archive unpacker (python)
    pkgs.pigz # parallel gzip backend
    pkgs.unzip # zip archive operations
    pkgs.xz # xz archiver
    pkgs.zip # zip archiver
    # Self-hosted web archiving toolkit (Internet Archive / archive.today /
    # IPFS): a few lookups a year, so the binary is built on first call.
    (onDemand {
      name = "wayback";
      attr = "wayback";
    })
  ];
}
