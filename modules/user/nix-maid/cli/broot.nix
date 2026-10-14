{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  cfg = config.features.cli.broot;
  brootRoot = config.lib.neg.path "files/shell/broot";
  brootRootLive = config.lib.neg.live "files/shell/broot";
in
lib.mkIf (cfg.enable or false) (
  lib.mkMerge [
    {
      environment.systemPackages = [ pkgs.broot ]; # terminal file manager for visualizing and navigating directory trees
    }

    (neg.mkHomeFiles {
      # Single config: broot reads conf.hjson first and conf.toml only when
      # the former is absent — shipping both silently shadowed the toml.
      ".config/broot/conf.toml".source = "${brootRootLive}/conf.toml";
      ".config/broot/to_stdout.hjson".source = "${brootRootLive}/to_stdout.hjson";
      ".config/broot/launcher".source = "${brootRoot}/launcher";
    })
  ]
)
