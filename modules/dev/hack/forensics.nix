{
  lib,
  config,
  pkgs,
  ...
}: let
  hackLib = import ./lib.nix {inherit lib config;};
  flags = config.features.dev.hack.forensics or {};
  groups = {
    fs = [
      pkgs.ddrescue
      pkgs.ext4magic
      pkgs.extundelete
      pkgs.sleuthkit
    ];
    stego = [
      pkgs.outguess
      pkgs.steghide
      pkgs.stegseek
      pkgs.stegsolve
      pkgs.zsteg
    ];
    analysis = [
      pkgs.ghidra-bin
      pkgs.capstone
      pkgs.volatility3
      pkgs.pdf-parser
    ];
    network = [
      pkgs.p0f
    ];
  };
  packages = hackLib.filterPackages (hackLib.mkGroupPackages flags groups);
in {
  config = lib.mkIf hackLib.enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
