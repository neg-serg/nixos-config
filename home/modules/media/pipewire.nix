{
  lib,
  config,
  ...
}: let
  filesRoot = "${config.neg.hmConfigRoot}/files";
in
  lib.mkIf (config.features.media.audio.core.enable or false) {
    xdg.configFile = {
      "wireplumber" = {
        source = filesRoot + "/media/wireplumber";
        recursive = true;
      };
      "pipewire" = {
        source = filesRoot + "/media/pipewire";
        recursive = true;
      };
    };
  }
