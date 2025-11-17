{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf (config.features.web.enable && config.features.web.tools.enable) {
  home.packages = config.lib.neg.pkgsList [
    pkgs.neg.awrit # render web pages inside Kitty terminal
    pkgs.gallery-dl # download image galleries/collections
    pkgs.monolith # download all webpage stuff as one file
    pkgs.pipe-viewer # lightweight youtube client
    pkgs.prettyping # fancy ping
    pkgs.whois # get domain info
    pkgs.xidel # download webpage parts
  ];
}
