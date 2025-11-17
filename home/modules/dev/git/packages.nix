{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
  mkIf config.features.dev.enable {
    home.packages = config.lib.neg.pkgsList [
      pkgs.act # run GitHub Actions locally
      pkgs.difftastic # syntax-aware diff viewer
      pkgs.gh # GitHub CLI
      pkgs.gist # manage GitHub gists
    ];
  }
