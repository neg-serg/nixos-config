{
  lib,
  config,
  ...
}: let
  sourceDir = config.neg.hmConfigRoot + "/files/misc/dosemu";
in
  lib.mkIf (builtins.pathExists sourceDir) {
    home.file.".dosemu" = {
      source = sourceDir;
      recursive = true;
    };
  }
