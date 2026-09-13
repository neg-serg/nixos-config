{
  config,
  lib,
  pkgs,
  neg,
  ...
}:
let
  cfg = config.features.dev;
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        environment.systemPackages = [ pkgs.tig ]; # Text-mode interface for git
      }
      (neg.mkHomeFiles {
        ".config/tig/config".text = builtins.readFile (config.lib.neg.path "files/cli/tig/config");
      })
    ]
  );
}
