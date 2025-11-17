{
  pkgs,
  config,
  ...
}: let
  groups = rec {
    fs = [
      pkgs.ddrescue # data recovery utility
      pkgs.ext4magic # recover deleted files from ext4
      pkgs.extundelete # undelete files from ext3/ext4
      pkgs.sleuthkit # filesystem forensics toolkit
    ];
    stego = [
      pkgs.outguess # universal steganography tool
      pkgs.steghide # hide/extract data in images/audio
      pkgs.stegseek # crack steghide passwords fast
      pkgs.stegsolve # image steganography analyzer/solver
      pkgs.zsteg # detect hidden data in PNG/BMP
    ];
    analysis = [
      pkgs.ghidra-bin # reverse engineering suite
      pkgs.capstone # multi-arch disassembly engine
      pkgs.volatility3 # memory forensics framework
      pkgs.pdf-parser # analyze/parse PDF documents
    ];
    network = [
      pkgs.p0f # passive OS/network fingerprinting
    ];
  };
in {
  home.packages = config.lib.neg.pkgsList (
    config.lib.neg.mkEnabledList config.features.dev.hack.forensics groups
  );
}
