{
  lib,
  config,
  ...
}: let
  walkerSrc = config.neg.hmConfigRoot + "/files/walker";
in
  lib.mkIf (config.features.gui.enable && builtins.pathExists walkerSrc) {
    xdg.configFile."walker".source = walkerSrc;
  }
