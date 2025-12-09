{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf config.features.dev.enable {
  programs.gh = {
    enable = true;
    extensions = [pkgs.gh-dash];
    settings = {
      git_protocol = "ssh";
      editor = "nvim";
    };
  };
}
