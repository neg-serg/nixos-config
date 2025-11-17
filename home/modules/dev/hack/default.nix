{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  groups = rec {
    secrets = [
      pkgs.gitleaks # scan repositories for secrets
      pkgs.git-secrets # prevent committing secrets to git
    ];
    reverse = [
      # pkgs.binwalk # analyze binaries for embedded files
      pkgs.capstone # disassembly framework
    ];
    crawl = [
      pkgs.katana # modern web crawler/spider
    ];
  };
in {
  imports = [
    ./forensics
    ./pentest
    ./sdr
  ];
  config = mkIf (config.features.dev.enable && config.features.hack.enable) {
    home.packages = config.lib.neg.pkgsList (
      config.lib.neg.mkEnabledList config.features.dev.hack.core groups
    );
  };
}
