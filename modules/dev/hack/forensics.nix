{
  lib,
  config,
  pkgs,
  ...
}:
let
  hackLib = import ./lib.nix { inherit lib config; };
  flags = config.features.dev.hack.forensics or { };
  groups = {
    fs = [
      pkgs.ddrescue # block-level data recovery tool
      pkgs.ext4magic # recover deleted ext4 files
      pkgs.extundelete # alternative ext4 undelete utility
      pkgs.sleuthkit # forensic filesystem toolkit (tsk_recover, etc.)
    ];
    stego = [
      pkgs.outguess # JPEG steganography tool
      pkgs.steghide # embed/extract data from images/audio
      pkgs.stegseek # ultra-fast steghide cracker
      pkgs.stegsolve # visual stego analyzer for images
      pkgs.zsteg # PNG/BMP steganography detector
    ];
    analysis = [
      pkgs.ghidra-bin # NSA's reverse-engineering suite
      pkgs.capstone # disassembly engine for binary analysis
      pkgs.volatility3 # memory forensics framework
      pkgs.pdf-parser # inspect malicious PDF objects
    ];
    network = [
      pkgs.p0f # passive OS/network fingerprinting
    ];
  };
  packages = hackLib.filterPackages (hackLib.mkGroupPackages flags groups);
in
{
  config = lib.mkIf hackLib.enabled {
    # environment.systemPackages = lib.mkAfter packages; # Moved to devShells.pentest
  };
}
